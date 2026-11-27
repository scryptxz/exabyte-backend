-- | CRUD de endereços de entrega.
--   O cliente informa só CEP, número e complemento; logradouro, bairro,
--   cidade e UF são preenchidos automaticamente pela API ViaCEP.
module Handler.Endereco where

import Control.Monad (when)
import Data.Aeson (withObject, (.:), (.:?))
import Data.Text (Text)
import qualified Data.Text as T
import Database.Persist
import Network.HTTP.Types.Status (status201)
import Yesod.Core
import Yesod.Persist.Core (runDB, get404)

import Foundation
import Handler.Comum
import Models
import Servicos.Externos

-- | Corpo aceito no POST/PUT: {"cep": "01001-000", "numero": "100", "complemento": "Apto 12"}
data EnderecoEntrada = EnderecoEntrada
  { eeCep         :: Text
  , eeNumero      :: Text
  , eeComplemento :: Maybe Text
  }

instance FromJSON EnderecoEntrada where
  parseJSON = withObject "EnderecoEntrada" $ \o ->
    EnderecoEntrada
      <$> o .:  "cep"
      <*> o .:  "numero"
      <*> o .:? "complemento"

-- | Consulta o ViaCEP e monta o registro completo do endereço do cliente.
--   CEP inválido/inexistente ou falha na API externa => HTTP 400.
montarEndereco :: ClienteId -> EnderecoEntrada -> Handler Endereco
montarEndereco cid entrada = do
  validarOu400 [obrigatorio "numero" (eeNumero entrada)]
  app <- getYesod
  resultado <- liftIO $ buscarCep (appHttp app) (eeCep entrada)
  case resultado of
    Left msg -> erro400 [msg]
    Right vc -> return Endereco
      { enderecoClienteId   = cid
      , enderecoCep         = vcCep vc
      , enderecoLogradouro  = vcLogradouro vc
      , enderecoNumero      = T.strip (eeNumero entrada)
      , enderecoComplemento = T.strip <$> eeComplemento entrada
      , enderecoBairro      = vcBairro vc
      , enderecoCidade      = vcCidade vc
      , enderecoUf          = vcUf vc
      }

-- | GET /api/clientes/#id/enderecos
getClienteEnderecosR :: ClienteId -> Handler Value
getClienteEnderecosR cid = do
  enderecos <- runDB $ do
    _ <- get404 cid
    selectList [EnderecoClienteId ==. cid] [Asc EnderecoId]
  returnJson enderecos

-- | POST /api/clientes/#id/enderecos
postClienteEnderecosR :: ClienteId -> Handler Value
postClienteEnderecosR cid = do
  _ <- runDB $ get404 cid
  entrada  <- requireCheckJsonBody :: Handler EnderecoEntrada
  endereco <- montarEndereco cid entrada
  eid <- runDB $ insert endereco
  sendStatusJSON status201 (Entity eid endereco)

-- | GET /api/enderecos/#id
getEnderecoR :: EnderecoId -> Handler Value
getEnderecoR eid = do
  endereco <- runDB $ get404 eid
  returnJson (Entity eid endereco)

-- | PUT /api/enderecos/#id  (consulta o ViaCEP de novo; o dono do endereço não muda)
putEnderecoR :: EnderecoId -> Handler Value
putEnderecoR eid = do
  atual    <- runDB $ get404 eid
  entrada  <- requireCheckJsonBody :: Handler EnderecoEntrada
  endereco <- montarEndereco (enderecoClienteId atual) entrada
  runDB $ replace eid endereco
  returnJson (Entity eid endereco)

-- | DELETE /api/enderecos/#id  (bloqueado se o endereço já foi usado em pedidos)
deleteEnderecoR :: EnderecoId -> Handler Value
deleteEnderecoR eid = do
  runDB $ do
    _ <- get404 eid
    pedidos <- count [PedidoEnderecoId ==. eid]
    when (pedidos > 0) $
      conflito "Não é possível excluir: o endereço foi usado em pedidos"
    delete eid
  semConteudo
