-- | Pedidos de compra: criação com baixa de estoque, consulta detalhada,
--   mudança de status (com devolução de estoque ao cancelar) e exclusão.
module Handler.Pedido where

import Control.Monad (forM, forM_, when)
import Data.Aeson (withObject, (.:))
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Database.Persist
import Database.Persist.Sql (SqlPersistT, fromSqlKey)
import Network.HTTP.Types.Status (status201)
import Yesod.Core
import Yesod.Persist.Core (runDB, get404)

import Foundation
import Handler.Comum
import Models

-- | Item do corpo do POST: {"produtoId": 3, "quantidade": 2}
data ItemEntrada = ItemEntrada
  { ieProdutoId  :: ProdutoId
  , ieQuantidade :: Int
  }

instance FromJSON ItemEntrada where
  parseJSON = withObject "ItemEntrada" $ \o ->
    ItemEntrada <$> o .: "produtoId" <*> o .: "quantidade"

-- | Corpo do POST: {"clienteId": 1, "enderecoId": 1, "itens": [...]}
--   O preço NÃO vem do cliente: é lido do banco no momento da compra.
data PedidoEntrada = PedidoEntrada
  { peClienteId  :: ClienteId
  , peEnderecoId :: EnderecoId
  , peItens      :: [ItemEntrada]
  }

instance FromJSON PedidoEntrada where
  parseJSON = withObject "PedidoEntrada" $ \o ->
    PedidoEntrada <$> o .: "clienteId" <*> o .: "enderecoId" <*> o .: "itens"

-- | Corpo do PUT: {"status": "pago"}
newtype StatusEntrada = StatusEntrada { seStatus :: Text }

instance FromJSON StatusEntrada where
  parseJSON = withObject "StatusEntrada" $ \o -> StatusEntrada <$> o .: "status"

statusValidos :: [Text]
statusValidos = ["pendente", "pago", "enviado", "entregue", "cancelado"]

-- | Monta o JSON completo do pedido: o pedido, o cliente, o endereço e os itens
--   (com o nome do produto, para o frontend não precisar de outra chamada).
detalharPedido :: Entity Pedido -> SqlPersistT Handler Value
detalharPedido (Entity pid pedido) = do
  cliente  <- get (pedidoClienteId pedido)
  endereco <- get (pedidoEnderecoId pedido)
  itens    <- selectList [ItemPedidoPedidoId ==. pid] [Asc ItemPedidoId]
  itensJson <- forM itens $ \(Entity _ item) -> do
    produto <- get (itemPedidoProdutoId item)
    return $ object
      [ "produtoId"     .= itemPedidoProdutoId item
      , "produtoNome"   .= maybe "(produto removido)" produtoNome produto
      , "quantidade"    .= itemPedidoQuantidade item
      , "precoUnitario" .= itemPedidoPrecoUnitario item
      ]
  return $ object
    [ "pedido"   .= Entity pid pedido
    , "cliente"  .= (Entity (pedidoClienteId pedido) <$> cliente)
    , "endereco" .= (Entity (pedidoEnderecoId pedido) <$> endereco)
    , "itens"    .= itensJson
    ]

-- | Devolve ao estoque as quantidades de todos os itens do pedido.
devolverEstoque :: PedidoId -> SqlPersistT Handler ()
devolverEstoque pid = do
  itens <- selectList [ItemPedidoPedidoId ==. pid] []
  forM_ itens $ \(Entity _ item) ->
    update (itemPedidoProdutoId item) [ProdutoEstoque +=. itemPedidoQuantidade item]

-- | GET /api/pedidos?cliente=1  (filtro por cliente é opcional; mais recentes primeiro)
getPedidosR :: Handler Value
getPedidosR = do
  cliente <- paramChave "cliente"
  let filtros = maybe [] (\c -> [PedidoClienteId ==. c]) cliente
  pedidos <- runDB $ selectList filtros [Desc PedidoCriadoEm] >>= mapM detalharPedido
  returnJson pedidos

-- | POST /api/pedidos
--   Tudo roda numa única transação: se qualquer validação falhar (erro400),
--   nada é gravado e nenhum estoque é baixado.
postPedidosR :: Handler Value
postPedidosR = do
  entrada <- requireCheckJsonBody :: Handler PedidoEntrada
  validarOu400
    [ if null (peItens entrada) then Just "o pedido deve ter pelo menos um item" else Nothing
    , if any ((<= 0) . ieQuantidade) (peItens entrada)
        then Just "quantidade deve ser maior que zero" else Nothing
    ]
  agora <- liftIO getCurrentTime
  resposta <- runDB $ do
    cliente  <- get (peClienteId entrada)
    endereco <- get (peEnderecoId entrada)
    validarOu400
      [ if isNothing cliente then Just "cliente informado não existe" else Nothing
      , if isNothing endereco then Just "endereço informado não existe" else Nothing
      ]
    validarOu400
      [ case endereco of
          Just e | enderecoClienteId e /= peClienteId entrada ->
            Just "o endereço não pertence a este cliente"
          _ -> Nothing
      ]
    -- Junta itens repetidos do mesmo produto antes de conferir o estoque.
    let quantidades = Map.toList $ Map.fromListWith (+)
          [ (ieProdutoId i, ieQuantidade i) | i <- peItens entrada ]
    itens <- forM quantidades $ \(prodId, qtd) -> do
      produto <- get prodId
      case produto of
        Nothing -> erro400 ["produto " <> tshow (fromSqlKey prodId) <> " não existe"]
        Just p -> do
          when (produtoEstoque p < qtd) $
            erro400 [ "estoque insuficiente para " <> produtoNome p
                      <> " (disponível: " <> tshow (produtoEstoque p) <> ")" ]
          return (prodId, p, qtd)
    let total  = arredondar $ sum [ produtoPreco p * fromIntegral q | (_, p, q) <- itens ]
        pedido = Pedido
          { pedidoClienteId  = peClienteId entrada
          , pedidoEnderecoId = peEnderecoId entrada
          , pedidoCriadoEm   = agora
          , pedidoStatus     = "pendente"
          , pedidoTotal      = total
          }
    pid <- insert pedido
    forM_ itens $ \(prodId, p, q) -> do
      -- Guarda o preço do momento da compra: mudar o preço do produto depois
      -- não altera pedidos antigos.
      insert_ (ItemPedido pid prodId q (produtoPreco p))
      update prodId [ProdutoEstoque -=. q]
    detalharPedido (Entity pid pedido)
  sendStatusJSON status201 resposta

-- | GET /api/pedidos/#id
getPedidoR :: PedidoId -> Handler Value
getPedidoR pid = do
  resposta <- runDB $ do
    pedido <- get404 pid
    detalharPedido (Entity pid pedido)
  returnJson resposta

-- | PUT /api/pedidos/#id  (altera somente o status)
--   Cancelar devolve o estoque; um pedido cancelado não pode voltar a outro status.
putPedidoR :: PedidoId -> Handler Value
putPedidoR pid = do
  entrada <- requireCheckJsonBody :: Handler StatusEntrada
  let novo = T.toLower (T.strip (seStatus entrada))
  validarOu400
    [ if novo `elem` statusValidos then Nothing
        else Just ("status inválido. Use: " <> T.intercalate ", " statusValidos) ]
  resposta <- runDB $ do
    pedido <- get404 pid
    let atual = pedidoStatus pedido
    when (atual == "cancelado" && novo /= "cancelado") $
      conflito "Pedido cancelado não pode ser reaberto"
    when (novo == "cancelado" && atual /= "cancelado") $
      devolverEstoque pid
    update pid [PedidoStatus =. novo]
    detalharPedido (Entity pid pedido { pedidoStatus = novo })
  returnJson resposta

-- | DELETE /api/pedidos/#id
--   Se o pedido ainda não saiu da loja (pendente ou pago), o estoque volta.
--   Os itens são apagados antes do pedido por causa da chave estrangeira.
deletePedidoR :: PedidoId -> Handler Value
deletePedidoR pid = do
  runDB $ do
    pedido <- get404 pid
    when (pedidoStatus pedido `elem` ["pendente", "pago"]) $
      devolverEstoque pid
    deleteWhere [ItemPedidoPedidoId ==. pid]
    delete pid
  semConteudo
