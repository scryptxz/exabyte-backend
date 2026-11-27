-- | Ponto de entrada da API: liga as rotas aos handlers (dispatch),
--   conecta no PostgreSQL, roda a migração e os dados de exemplo
--   e sobe o servidor Warp com CORS liberado para o frontend.
module Application (iniciar) where

import Control.Monad.Logger (runStdoutLoggingT)
import qualified Data.ByteString.Char8 as BS8
import Data.Maybe (fromMaybe)
import Database.Persist.Postgresql (createPostgresqlPool, rawExecute, runMigration, runSqlPool)
import Network.HTTP.Client.TLS (newTlsManager)
import Network.Wai.Handler.Warp (run)
import Network.Wai.Middleware.Cors
import System.Environment (lookupEnv)
import Text.Read (readMaybe)
import Yesod.Core

import Foundation
import Handler.Avaliacao
import Handler.Categoria
import Handler.Cliente
import Handler.Endereco
import Handler.Externo
import Handler.Fabricante
import Handler.Pedido
import Handler.Produto
import Models
import Seed (popularBanco)

-- Gera a instância YesodDispatch: para cada rota de config/routes, chama o
-- handler com o nome correspondente (getProdutosR, postPedidosR, ...).
-- Fica aqui, e não em Foundation, porque precisa enxergar todos os handlers.
mkYesodDispatch "App" resourcesApp

-- | Conexão padrão para desenvolvimento local (sobrescrita por DATABASE_URL).
conexaoPadrao :: BS8.ByteString
conexaoPadrao = "host=localhost port=5432 user=postgres password=postgres dbname=exabyte"

-- | O frontend roda em outra origem (outra porta), então o navegador exige CORS.
--   O wai-cors também responde sozinho às requisições OPTIONS (preflight).
politicaCors :: CorsResourcePolicy
politicaCors = simpleCorsResourcePolicy
  { corsMethods        = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  , corsRequestHeaders = ["Content-Type"]
  }

iniciar :: IO ()
iniciar = do
  conexao <- maybe conexaoPadrao BS8.pack <$> lookupEnv "DATABASE_URL"
  porta   <- fromMaybe 3000 . (>>= readMaybe) <$> lookupEnv "PORT"

  pool <- runStdoutLoggingT $ createPostgresqlPool conexao 10

  flip runSqlPool pool $ do
    -- Colunas de uma versão antiga da tabela pedido (conversão para dólar).
    -- O runMigration não apaga colunas sozinho (é uma mudança "insegura"),
    -- então elas são removidas aqui antes da migração.
    rawExecute "ALTER TABLE IF EXISTS pedido DROP COLUMN IF EXISTS total_dolar" []
    rawExecute "ALTER TABLE IF EXISTS pedido DROP COLUMN IF EXISTS cotacao_dolar" []
    runMigration migrateAll
    popularBanco

  manager <- newTlsManager
  app <- toWaiApp (App pool manager)
  putStrLn $ "Exabyte API rodando em http://localhost:" <> show porta
  run porta (cors (const (Just politicaCors)) app)
