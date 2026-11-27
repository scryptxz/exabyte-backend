-- | Avaliações (nota de 1 a 5) dos clientes sobre os produtos.
module Handler.Avaliacao where

import Control.Monad (forM, when)
import Data.Aeson (withObject, (.:), (.:?))
import Data.Maybe (isNothing)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time (getCurrentTime)
import Database.Persist
import Network.HTTP.Types.Status (status201)
import Yesod.Core
import Yesod.Persist.Core (runDB, get404)

import Foundation
import Handler.Comum
import Models

-- | Corpo do POST/PUT: {"clienteId": 1, "nota": 5, "comentario": "..."}
--   No PUT o clienteId é ignorado (o autor da avaliação não muda).
data AvaliacaoEntrada = AvaliacaoEntrada
  { aeClienteId  :: Maybe ClienteId
  , aeNota       :: Int
  , aeComentario :: Maybe Text
  }

instance FromJSON AvaliacaoEntrada where
  parseJSON = withObject "AvaliacaoEntrada" $ \o ->
    AvaliacaoEntrada
      <$> o .:? "clienteId"
      <*> o .:  "nota"
      <*> o .:? "comentario"

validarNota :: Int -> Maybe Text
validarNota n
  | n < 1 || n > 5 = Just "nota deve estar entre 1 e 5"
  | otherwise      = Nothing

-- | Comentário só com espaços vira Nothing.
limparComentario :: Maybe Text -> Maybe Text
limparComentario c = case T.strip <$> c of
  Just t | not (T.null t) -> Just t
  _                       -> Nothing

-- | GET /api/produtos/#id/avaliacoes
--   Resposta: {"media": 4.5, "quantidade": 2, "avaliacoes": [{"avaliacao": {...}, "clienteNome": "..."}]}
getProdutoAvaliacoesR :: ProdutoId -> Handler Value
getProdutoAvaliacoesR pid = do
  (avaliacoes, lista) <- runDB $ do
    _ <- get404 pid
    avs <- selectList [AvaliacaoProdutoId ==. pid] [Desc AvaliacaoCriadaEm]
    itens <- forM avs $ \ent@(Entity _ av) -> do
      cliente <- get (avaliacaoClienteId av)
      return $ object
        [ "avaliacao"   .= ent
        , "clienteNome" .= (clienteNome <$> cliente)
        ]
    return (avs, itens)
  let notas = map (avaliacaoNota . entityVal) avaliacoes
      quantidade = length notas
      media :: Double
      media | quantidade == 0 = 0
            | otherwise = arredondar (fromIntegral (sum notas) / fromIntegral quantidade)
  returnJson $ object
    [ "media"      .= media
    , "quantidade" .= quantidade
    , "avaliacoes" .= lista
    ]

-- | POST /api/produtos/#id/avaliacoes  (um cliente avalia cada produto só uma vez)
postProdutoAvaliacoesR :: ProdutoId -> Handler Value
postProdutoAvaliacoesR pid = do
  entrada <- requireCheckJsonBody :: Handler AvaliacaoEntrada
  validarOu400 [validarNota (aeNota entrada)]
  cid <- maybe (erro400 ["clienteId é obrigatório"]) return (aeClienteId entrada)
  agora <- liftIO getCurrentTime
  let nova = Avaliacao
        { avaliacaoProdutoId  = pid
        , avaliacaoClienteId  = cid
        , avaliacaoNota       = aeNota entrada
        , avaliacaoComentario = limparComentario (aeComentario entrada)
        , avaliacaoCriadaEm   = agora
        }
  aid <- runDB $ do
    _ <- get404 pid
    cliente <- get cid
    when (isNothing cliente) $ erro400 ["cliente informado não existe"]
    -- UniqueAvaliacao (produtoId, clienteId) impede a segunda avaliação.
    resultado <- insertUnique nova
    maybe (conflito "Este cliente já avaliou este produto") return resultado
  sendStatusJSON status201 (Entity aid nova)

-- | PUT /api/avaliacoes/#id  (altera nota e comentário)
putAvaliacaoR :: AvaliacaoId -> Handler Value
putAvaliacaoR aid = do
  entrada <- requireCheckJsonBody :: Handler AvaliacaoEntrada
  validarOu400 [validarNota (aeNota entrada)]
  atualizada <- runDB $ do
    atual <- get404 aid
    let nova = atual
          { avaliacaoNota       = aeNota entrada
          , avaliacaoComentario = limparComentario (aeComentario entrada)
          }
    replace aid nova
    return nova
  returnJson (Entity aid atualizada)

-- | DELETE /api/avaliacoes/#id
deleteAvaliacaoR :: AvaliacaoId -> Handler Value
deleteAvaliacaoR aid = do
  runDB $ do
    _ <- get404 aid
    delete aid
  semConteudo
