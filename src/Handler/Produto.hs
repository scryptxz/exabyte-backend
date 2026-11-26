-- | CRUD de produtos, com filtros por categoria, fabricante e busca textual.
module Handler.Produto where

import Control.Monad (when)
import Data.Maybe (catMaybes, isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import Database.Persist
import Database.Persist.Sql (SqlPersistT)
import Network.HTTP.Types.Status (status201)
import Yesod.Core
import Yesod.Persist.Core (runDB, get404)

import Foundation
import Handler.Comum
import Models

validarProduto :: Produto -> [Maybe Text]
validarProduto p =
  [ obrigatorio "nome" (produtoNome p)
  , obrigatorio "descricao" (produtoDescricao p)
  , if produtoPreco p <= 0 then Just "preco deve ser maior que zero" else Nothing
  , if produtoEstoque p < 0 then Just "estoque não pode ser negativo" else Nothing
  ]

-- | Confere se a categoria e o fabricante informados existem (chaves estrangeiras).
validarRelacionamentos :: Produto -> SqlPersistT Handler ()
validarRelacionamentos p = do
  cat <- get (produtoCategoriaId p)
  fab <- get (produtoFabricanteId p)
  validarOu400
    [ if isNothing cat then Just "categoria informada não existe" else Nothing
    , if isNothing fab then Just "fabricante informado não existe" else Nothing
    ]

-- | Filtro ILIKE do PostgreSQL (busca sem diferenciar maiúsculas/minúsculas).
contem :: EntityField Produto Text -> Text -> Filter Produto
contem campo texto =
  Filter campo (FilterValue ("%" <> texto <> "%")) (BackendSpecificFilter "ILIKE")

-- | GET /api/produtos?categoria=1&fabricante=2&busca=ryzen
getProdutosR :: Handler Value
getProdutosR = do
  categoria  <- paramChave "categoria"
  fabricante <- paramChave "fabricante"
  busca      <- lookupGetParam "busca"
  let filtros = catMaybes
        [ (ProdutoCategoriaId ==.) <$> categoria
        , (ProdutoFabricanteId ==.) <$> fabricante
        , contem ProdutoNome <$> (T.strip <$> busca >>= naoVazio)
        ]
      naoVazio t = if T.null t then Nothing else Just t
  produtos <- runDB $ selectList filtros [Asc ProdutoNome]
  returnJson produtos

-- | POST /api/produtos
postProdutosR :: Handler Value
postProdutosR = do
  produto <- requireCheckJsonBody :: Handler Produto
  validarOu400 (validarProduto produto)
  pid <- runDB $ do
    validarRelacionamentos produto
    insert produto
  sendStatusJSON status201 (Entity pid produto)

-- | GET /api/produtos/#id
getProdutoR :: ProdutoId -> Handler Value
getProdutoR pid = do
  produto <- runDB $ get404 pid
  returnJson (Entity pid produto)

-- | PUT /api/produtos/#id
putProdutoR :: ProdutoId -> Handler Value
putProdutoR pid = do
  _ <- runDB $ get404 pid
  produto <- requireCheckJsonBody :: Handler Produto
  validarOu400 (validarProduto produto)
  runDB $ do
    validarRelacionamentos produto
    replace pid produto
  returnJson (Entity pid produto)

-- | DELETE /api/produtos/#id  (bloqueado se o produto já foi vendido;
--   as avaliações do produto são excluídas junto)
deleteProdutoR :: ProdutoId -> Handler Value
deleteProdutoR pid = do
  runDB $ do
    _ <- get404 pid
    vendas <- count [ItemPedidoProdutoId ==. pid]
    when (vendas > 0) $
      conflito "Não é possível excluir: o produto já aparece em pedidos. Zere o estoque em vez disso."
    deleteWhere [AvaliacaoProdutoId ==. pid]
    delete pid
  semConteudo
