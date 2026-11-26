-- | CRUD de clientes.
module Handler.Cliente where

import Control.Monad (when)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import Database.Persist
import Network.HTTP.Types.Status (status201)
import Yesod.Core
import Yesod.Persist.Core (runDB, get404)

import Foundation
import Handler.Comum
import Models

-- | Normaliza os dados antes de salvar (CPF só com dígitos, e-mail minúsculo).
normalizarCliente :: Cliente -> Cliente
normalizarCliente c = c
  { clienteNome  = T.strip (clienteNome c)
  , clienteEmail = T.toLower (T.strip (clienteEmail c))
  , clienteCpf   = apenasDigitos (clienteCpf c)
  }

validarCliente :: Cliente -> [Maybe Text]
validarCliente c =
  [ obrigatorio "nome" (clienteNome c)
  , if "@" `T.isInfixOf` clienteEmail c && "." `T.isInfixOf` clienteEmail c
      then Nothing else Just "email inválido"
  , if T.length (clienteCpf c) /= 11 then Just "cpf deve conter 11 dígitos" else Nothing
  ]

-- | GET /api/clientes
getClientesR :: Handler Value
getClientesR = do
  clientes <- runDB $ selectList [] [Asc ClienteNome]
  returnJson clientes

-- | POST /api/clientes
postClientesR :: Handler Value
postClientesR = do
  cliente <- normalizarCliente <$> (requireCheckJsonBody :: Handler Cliente)
  validarOu400 (validarCliente cliente)
  resultado <- runDB $ insertUnique cliente
  case resultado of
    Nothing  -> conflito "Já existe um cliente com esse e-mail ou CPF"
    Just cid -> sendStatusJSON status201 (Entity cid cliente)

-- | GET /api/clientes/#id
getClienteR :: ClienteId -> Handler Value
getClienteR cid = do
  cliente <- runDB $ get404 cid
  returnJson (Entity cid cliente)

-- | PUT /api/clientes/#id
putClienteR :: ClienteId -> Handler Value
putClienteR cid = do
  _ <- runDB $ get404 cid
  cliente <- normalizarCliente <$> (requireCheckJsonBody :: Handler Cliente)
  validarOu400 (validarCliente cliente)
  runDB $ do
    duplicado <- checkUniqueUpdateable (Entity cid cliente)
    when (isJust duplicado) $ conflito "Já existe outro cliente com esse e-mail ou CPF"
    replace cid cliente
  returnJson (Entity cid cliente)

-- | DELETE /api/clientes/#id
--   Bloqueado se o cliente tiver pedidos; caso contrário remove também
--   seus endereços e avaliações.
deleteClienteR :: ClienteId -> Handler Value
deleteClienteR cid = do
  runDB $ do
    _ <- get404 cid
    pedidos <- count [PedidoClienteId ==. cid]
    when (pedidos > 0) $
      conflito "Não é possível excluir: o cliente possui pedidos"
    deleteWhere [AvaliacaoClienteId ==. cid]
    deleteWhere [EnderecoClienteId ==. cid]
    delete cid
  semConteudo
