-- | CRUD de fabricantes.
module Handler.Fabricante where

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

validarFabricante :: Fabricante -> [Maybe Text]
validarFabricante f = [obrigatorio "nome" (fabricanteNome f)]

-- | GET /api/fabricantes
getFabricantesR :: Handler Value
getFabricantesR = do
  fabricantes <- runDB $ selectList [] [Asc FabricanteNome]
  returnJson fabricantes

-- | POST /api/fabricantes
postFabricantesR :: Handler Value
postFabricantesR = do
  fabricante <- requireCheckJsonBody :: Handler Fabricante
  validarOu400 (validarFabricante fabricante)
  resultado <- runDB $ insertUnique fabricante
  case resultado of
    Nothing  -> conflito "Já existe um fabricante com esse nome"
    Just fid -> sendStatusJSON status201 (Entity fid fabricante)

-- | GET /api/fabricantes/#id
getFabricanteR :: FabricanteId -> Handler Value
getFabricanteR fid = do
  fabricante <- runDB $ get404 fid
  returnJson (Entity fid fabricante)

-- | PUT /api/fabricantes/#id
putFabricanteR :: FabricanteId -> Handler Value
putFabricanteR fid = do
  _ <- runDB $ get404 fid
  fabricante <- requireCheckJsonBody :: Handler Fabricante
  validarOu400 (validarFabricante fabricante)
  runDB $ do
    duplicado <- checkUniqueUpdateable (Entity fid fabricante)
    when (isJust duplicado) $ conflito "Já existe um fabricante com esse nome"
    replace fid fabricante
  returnJson (Entity fid fabricante)

-- | DELETE /api/fabricantes/#id  (bloqueado se houver produtos do fabricante)
deleteFabricanteR :: FabricanteId -> Handler Value
deleteFabricanteR fid = do
  runDB $ do
    _ <- get404 fid
    produtos <- count [ProdutoFabricanteId ==. fid]
    when (produtos > 0) $
      conflito "Não é possível excluir: existem produtos deste fabricante"
    delete fid
  semConteudo
