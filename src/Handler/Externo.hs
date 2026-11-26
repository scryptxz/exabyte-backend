-- | Endpoint que expõe ao frontend os dados do ViaCEP.
module Handler.Externo where

import Data.Text (Text)
import Yesod.Core

import Foundation
import Handler.Comum
import Servicos.Externos

-- | GET /api/externo/cep/01001000 -> endereço vindo do ViaCEP
getCepR :: Text -> Handler Value
getCepR cep = do
  app <- getYesod
  resultado <- liftIO $ buscarCep (appHttp app) cep
  case resultado of
    Left msg       -> erro400 [msg]
    Right endereco -> returnJson endereco
