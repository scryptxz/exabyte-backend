# Exabyte API

API REST da **Exabyte**, loja de peças de computador. Feita em **Haskell** com
**Yesod** e **Persistent** sobre **PostgreSQL**, e integrada à API pública
**ViaCEP** para preencher endereços a partir do CEP.

## Tecnologias

- GHC 9.10 / Stack (snapshot `lts-24.67`)
- Yesod Core + Yesod Persistent
- Persistent + persistent-postgresql (modelo, migração automática e consultas)
- Warp (servidor HTTP) + wai-cors (CORS para o frontend)
- http-client-tls (chamadas ao ViaCEP)

## Como rodar

1. Instale o [Stack](https://docs.haskellstack.org/) e o PostgreSQL.
2. Crie o banco:

   ```sql
   CREATE DATABASE exabyte;
   ```

3. Configure a conexão (opcional). Sem a variável, a API usa
   `host=localhost port=5432 user=postgres password=postgres dbname=exabyte`.

   ```bash
   export DATABASE_URL="host=localhost port=5432 user=postgres password=SUA_SENHA dbname=exabyte"
   export PORT=3000   # opcional, padrão 3000
   ```

4. Compile e rode:

   ```bash
   stack build
   stack exec exabyte-api
   ```

Na primeira execução a API cria as tabelas (migração automática) e insere
dados de exemplo: categorias, fabricantes, 11 produtos, um cliente de
demonstração com endereço e duas avaliações. Os dados de exemplo só são
inseridos quando o banco está vazio.

## Estrutura

```
app/Main.hs               ponto de entrada (chama Application.iniciar)
config/routes             definição das rotas
src/Models.hs             as 8 tabelas (Persistent)
src/Foundation.hs         tipo App, instâncias Yesod, erros em JSON
src/Application.hs        dispatch, CORS, conexão, migração
src/Seed.hs               dados de exemplo
src/Handler/Comum.hs      helpers de resposta e validação
src/Handler/*.hs          um módulo por recurso da API
src/Servicos/Externos.hs  cliente do ViaCEP
```

## Modelo de dados

| Tabela       | Descrição                                               |
|--------------|---------------------------------------------------------|
| `categoria`  | Categoria de peça (nome único)                          |
| `fabricante` | Marca (nome único)                                      |
| `produto`    | Peça à venda; FK para categoria e fabricante            |
| `cliente`    | Cliente; e-mail e CPF únicos                            |
| `endereco`   | Endereço de entrega do cliente (preenchido pelo ViaCEP) |
| `pedido`     | Pedido de compra, com status e total                    |
| `item_pedido`| Itens do pedido, com o preço no momento da compra       |
| `avaliacao`  | Nota 1–5 de um cliente para um produto (uma por par)    |

## Endpoints

Todas as respostas são JSON. Erros vêm como `{"erro": "..."}` ou
`{"erros": ["..."]}`.

### Catálogo

| Método | Rota | Descrição |
|---|---|---|
| GET / POST | `/api/categorias` | Lista / cria categoria |
| GET / PUT / DELETE | `/api/categorias/{id}` | Detalha / altera / exclui (bloqueado se houver produtos) |
| GET / POST | `/api/fabricantes` | Lista / cria fabricante |
| GET / PUT / DELETE | `/api/fabricantes/{id}` | Detalha / altera / exclui |
| GET / POST | `/api/produtos` | Lista (filtros `?categoria=`, `?fabricante=`, `?busca=`) / cria |
| GET / PUT / DELETE | `/api/produtos/{id}` | Detalha / altera / exclui (bloqueado se já vendido) |

### Clientes e endereços

| Método | Rota | Descrição |
|---|---|---|
| GET / POST | `/api/clientes` | Lista / cria (valida CPF e e-mail) |
| GET / PUT / DELETE | `/api/clientes/{id}` | Detalha / altera / exclui (bloqueado se houver pedidos) |
| GET / POST | `/api/clientes/{id}/enderecos` | Lista / cria endereço do cliente |
| GET / PUT / DELETE | `/api/enderecos/{id}` | Detalha / altera / exclui (bloqueado se usado em pedidos) |

Para criar um endereço basta enviar CEP, número e complemento; o restante vem
do ViaCEP:

```json
{ "cep": "01001-000", "numero": "100", "complemento": "Apto 12" }
```

### Pedidos

| Método | Rota | Descrição |
|---|---|---|
| GET | `/api/pedidos` | Lista pedidos (filtro opcional `?cliente=`) |
| POST | `/api/pedidos` | Cria pedido, confere e baixa o estoque |
| GET | `/api/pedidos/{id}` | Pedido com cliente, endereço e itens |
| PUT | `/api/pedidos/{id}` | Altera o status |
| DELETE | `/api/pedidos/{id}` | Exclui (devolve o estoque se ainda pendente ou pago) |

```json
{
  "clienteId": 1,
  "enderecoId": 1,
  "itens": [ { "produtoId": 1, "quantidade": 2 } ]
}
```

Status possíveis: `pendente`, `pago`, `enviado`, `entregue`, `cancelado`.
Cancelar devolve o estoque, e um pedido cancelado não pode ser reaberto. O
preço de cada item é lido do banco no momento da compra.

### Avaliações

| Método | Rota | Descrição |
|---|---|---|
| GET | `/api/produtos/{id}/avaliacoes` | Média, quantidade e lista de avaliações |
| POST | `/api/produtos/{id}/avaliacoes` | Avalia o produto (`clienteId`, `nota`, `comentario`) |
| PUT / DELETE | `/api/avaliacoes/{id}` | Altera nota e comentário / exclui |

### API externa

| Método | Rota | Descrição |
|---|---|---|
| GET | `/api/externo/cep/{cep}` | Consulta o endereço de um CEP no ViaCEP |
