-- | Funções auxiliares usadas por todos os handlers:
--   respostas de erro padronizadas, validação e leitura de parâmetros.
module Handler.Comum
  ( erro400
  , validarOu400
  , conflito
  , semConteudo
  , obrigatorio
  , paramChave
  , tshow
  , apenasDigitos
  , arredondar
  ) where

import Data.Char (isDigit)
import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
import Database.Persist.Sql (ToBackendKey, SqlBackend, Key, toSqlKey)
import Network.HTTP.Types.Status (status204, status400, status409)
import Text.Read (readMaybe)
import Yesod.Core

-- | Interrompe a requisição com HTTP 400 e uma lista de erros.
--   Se chamado dentro de runDB, a transação é desfeita (rollback).
erro400 :: MonadHandler m => [Text] -> m a
erro400 erros = sendStatusJSON status400 (object ["erros" .= erros])

-- | Recebe validações (Nothing = ok, Just msg = erro) e responde 400 se houver erro.
validarOu400 :: MonadHandler m => [Maybe Text] -> m ()
validarOu400 checagens =
  case catMaybes checagens of
    []    -> return ()
    erros -> erro400 erros

-- | HTTP 409 Conflict (ex.: nome duplicado, registro em uso).
conflito :: MonadHandler m => Text -> m a
conflito msg = sendStatusJSON status409 (object ["erro" .= msg])

-- | HTTP 204 No Content (usado após DELETE).
semConteudo :: MonadHandler m => m a
semConteudo = sendResponseStatus status204 ()

-- | Validação de campo de texto obrigatório.
obrigatorio :: Text -> Text -> Maybe Text
obrigatorio campo valor
  | T.null (T.strip valor) = Just (campo <> " é obrigatório")
  | otherwise              = Nothing

-- | Lê um parâmetro da query string como chave (ex.: ?categoria=3).
paramChave :: (MonadHandler m, ToBackendKey SqlBackend r) => Text -> m (Maybe (Key r))
paramChave nome = do
  valor <- lookupGetParam nome
  return $ toSqlKey <$> (valor >>= readMaybe . T.unpack)

tshow :: Show a => a -> Text
tshow = T.pack . show

apenasDigitos :: Text -> Text
apenasDigitos = T.filter isDigit

-- | Arredonda valores monetários para 2 casas decimais.
arredondar :: Double -> Double
arredondar x = fromIntegral (round (x * 100) :: Integer) / 100
