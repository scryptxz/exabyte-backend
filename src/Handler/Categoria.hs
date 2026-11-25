-- | CRUD de categorias.
module Handler.Categoria where

import Control.Monad (when)
import Data.Maybe (isJust)
import Data.Text (Text)
import Database.Persist
import Network.HTTP.Types.Status (status201)
import Yesod.Core
import Yesod.Persist.Core (runDB, get404)

import Foundation
import Handler.Comum
import Models

validarCategoria :: Categoria -> [Maybe Text]
validarCategoria c = [obrigatorio "nome" (categoriaNome c)]

-- | GET /api/categorias
getCategoriasR :: Handler Value
getCategoriasR = do
  categorias <- runDB $ selectList [] [Asc CategoriaNome]
  returnJson categorias

-- | POST /api/categorias
postCategoriasR :: Handler Value
postCategoriasR = do
  categoria <- requireCheckJsonBody :: Handler Categoria
  validarOu400 (validarCategoria categoria)
  resultado <- runDB $ insertUnique categoria
  case resultado of
    Nothing  -> conflito "Já existe uma categoria com esse nome"
    Just cid -> sendStatusJSON status201 (Entity cid categoria)

-- | GET /api/categorias/#id
getCategoriaR :: CategoriaId -> Handler Value
getCategoriaR cid = do
  categoria <- runDB $ get404 cid
  returnJson (Entity cid categoria)

-- | PUT /api/categorias/#id
putCategoriaR :: CategoriaId -> Handler Value
putCategoriaR cid = do
  _ <- runDB $ get404 cid
  categoria <- requireCheckJsonBody :: Handler Categoria
  validarOu400 (validarCategoria categoria)
  runDB $ do
    duplicada <- checkUniqueUpdateable (Entity cid categoria)
    when (isJust duplicada) $ conflito "Já existe uma categoria com esse nome"
    replace cid categoria
  returnJson (Entity cid categoria)

-- | DELETE /api/categorias/#id  (bloqueado se houver produtos na categoria)
deleteCategoriaR :: CategoriaId -> Handler Value
deleteCategoriaR cid = do
  runDB $ do
    _ <- get404 cid
    produtos <- count [ProdutoCategoriaId ==. cid]
    when (produtos > 0) $
      conflito "Não é possível excluir: existem produtos nesta categoria"
    delete cid
  semConteudo
