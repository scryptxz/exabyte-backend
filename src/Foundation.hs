-- | Fundação da aplicação Yesod: o tipo App (estado global), a geração
--   das rotas a partir de config/routes e as instâncias Yesod/YesodPersist.
module Foundation where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8)
import Database.Persist.Sql (ConnectionPool, SqlBackend, runSqlPool)
import Network.HTTP.Client (Manager)
import Yesod.Core
import Yesod.Persist.Core

import Models

-- | Estado compartilhado por todas as requisições.
data App = App
  { appPool :: ConnectionPool -- ^ pool de conexões com o PostgreSQL
  , appHttp :: Manager        -- ^ cliente HTTP usado para chamar as APIs externas
  }

-- Gera o tipo de rotas (Route App), o tipo "Handler" e o "resourcesApp".
mkYesodData "App" $(parseRoutesFile "config/routes")

instance Yesod App where
  -- API REST sem estado: não usamos sessão/cookies.
  makeSessionBackend _ = return Nothing

  -- Todos os erros (404, 400, 405, 500) são devolvidos em JSON.
  errorHandler er = return $ toTypedContent $ object ["erro" .= mensagem er]
    where
      mensagem :: ErrorResponse -> Text
      mensagem NotFound             = "Recurso não encontrado"
      mensagem (InternalError t)    = "Erro interno: " <> t
      mensagem (InvalidArgs ts)     = "Requisição inválida: " <> T.intercalate "; " ts
      mensagem NotAuthenticated     = "Não autenticado"
      mensagem (PermissionDenied t) = "Permissão negada: " <> t
      mensagem (BadMethod m)        = "Método não permitido: " <> decodeUtf8 m

-- | Permite usar "runDB" nos handlers. Cada runDB roda numa transação.
instance YesodPersist App where
  type YesodPersistBackend App = SqlBackend
  runDB acao = do
    app <- getYesod
    runSqlPool acao (appPool app)
