-- | Consumo da API externa ViaCEP (https://viacep.com.br): endereço a partir do CEP.
module Servicos.Externos
  ( EnderecoViaCep (..)
  , buscarCep
  ) where

import Control.Exception (try)
import Data.Aeson
import Data.Aeson.Types (parseEither)
import Data.Text (Text)
import qualified Data.Text as T
import Network.HTTP.Client
import Network.HTTP.Types.Status (statusIsSuccessful)

import Handler.Comum (apenasDigitos)

-- | Somente os campos do ViaCEP que a loja utiliza.
data EnderecoViaCep = EnderecoViaCep
  { vcCep        :: Text
  , vcLogradouro :: Text
  , vcBairro     :: Text
  , vcCidade     :: Text
  , vcUf         :: Text
  } deriving Show

-- Resposta do ViaCEP: {"cep":"01001-000","logradouro":"Praça da Sé","bairro":"Sé","localidade":"São Paulo","uf":"SP",...}
-- Para CEP inexistente o ViaCEP responde {"erro": "true"}, que falha neste parser.
instance FromJSON EnderecoViaCep where
  parseJSON = withObject "ViaCEP" $ \o ->
    EnderecoViaCep
      <$> o .: "cep"
      <*> o .:? "logradouro" .!= ""
      <*> o .:? "bairro" .!= ""
      <*> o .: "localidade"
      <*> o .: "uf"

instance ToJSON EnderecoViaCep where
  toJSON e = object
    [ "cep"        .= vcCep e
    , "logradouro" .= vcLogradouro e
    , "bairro"     .= vcBairro e
    , "cidade"     .= vcCidade e
    , "uf"         .= vcUf e
    ]

-- | Faz um GET e devolve o corpo, tratando falhas de rede e status HTTP != 2xx.
httpGet :: Manager -> String -> IO (Either Text Value)
httpGet manager url = do
  resultado <- try $ do
    req  <- parseRequest url
    resp <- httpLbs req manager
    return resp
  return $ case resultado of
    Left (_ :: HttpException) -> Left "Falha de comunicação com a API externa"
    Right resp
      | not (statusIsSuccessful (responseStatus resp)) -> Left "API externa respondeu com erro"
      | otherwise -> either (const (Left "Resposta inválida da API externa")) Right
                            (eitherDecode (responseBody resp))

-- | Consulta o ViaCEP. Aceita CEP com ou sem máscara ("01001-000" ou "01001000").
buscarCep :: Manager -> Text -> IO (Either Text EnderecoViaCep)
buscarCep manager cepBruto
  | T.length cep /= 8 = return (Left "CEP deve conter 8 dígitos")
  | otherwise = do
      resposta <- httpGet manager ("https://viacep.com.br/ws/" <> T.unpack cep <> "/json/")
      return $ case resposta of
        Left e  -> Left e
        Right v -> either (const (Left "CEP não encontrado")) Right (parseEither parseJSON v)
  where
    cep = apenasDigitos cepBruto
