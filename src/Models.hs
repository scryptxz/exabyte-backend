-- | Modelo de dados (8 tabelas) definido com o DSL do Persistent.
--   A partir deste bloco o Template Haskell gera:
--     * os tipos Haskell (Categoria, Produto, ...) e suas chaves (CategoriaId, ...);
--     * as instâncias ToJSON/FromJSON (palavra "json" após o nome da entidade);
--     * a migração "migrateAll", que cria as tabelas, PKs, FKs e UNIQUEs no PostgreSQL.
module Models where

import Data.Text (Text)
import Data.Time (UTCTime)
import Database.Persist.TH

share [mkPersist sqlSettings, mkMigrate "migrateAll"] [persistLowerCase|
-- Categoria de peça (Processadores, Placas de vídeo, ...)
Categoria json
    nome        Text
    descricao   Text Maybe
    UniqueCategoriaNome nome
    deriving Show

-- Fabricante / marca (AMD, Intel, Corsair, ...)
Fabricante json
    nome        Text
    pais        Text Maybe
    site        Text Maybe
    UniqueFabricanteNome nome
    deriving Show

-- Produto vendido na loja. FK para Categoria e Fabricante.
Produto json
    nome          Text
    descricao     Text
    preco         Double
    estoque       Int
    imagemUrl     Text Maybe
    categoriaId   CategoriaId
    fabricanteId  FabricanteId
    deriving Show

-- Cliente da loja. E-mail e CPF são únicos.
Cliente json
    nome      Text
    email     Text
    cpf       Text
    telefone  Text Maybe
    UniqueClienteEmail email
    UniqueClienteCpf   cpf
    deriving Show

-- Endereço de entrega. Preenchido automaticamente pela API ViaCEP.
Endereco json
    clienteId    ClienteId
    cep          Text
    logradouro   Text
    numero       Text
    complemento  Text Maybe
    bairro       Text
    cidade       Text
    uf           Text
    deriving Show

-- Pedido de compra.
Pedido json
    clienteId     ClienteId
    enderecoId    EnderecoId
    criadoEm      UTCTime
    status        Text
    total         Double
    deriving Show

-- Itens de um pedido (relação N:N entre Pedido e Produto).
ItemPedido json
    pedidoId       PedidoId
    produtoId      ProdutoId
    quantidade     Int
    precoUnitario  Double
    deriving Show

-- Avaliação (nota 1 a 5) de um cliente sobre um produto. Uma por cliente/produto.
Avaliacao json
    produtoId   ProdutoId
    clienteId   ClienteId
    nota        Int
    comentario  Text Maybe
    criadaEm    UTCTime
    UniqueAvaliacao produtoId clienteId
    deriving Show
|]
