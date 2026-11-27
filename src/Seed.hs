-- | Dados de exemplo inseridos na primeira execução (banco vazio),
--   para o frontend já ter catálogo, um cliente e avaliações para exibir.
module Seed (popularBanco) where

import Control.Monad (when)
import Control.Monad.IO.Class (liftIO)
import Data.Time (getCurrentTime)
import Database.Persist
import Database.Persist.Sql (SqlPersistT)

import Models

-- | Só popula se ainda não existir nenhuma categoria; assim reiniciar o
--   servidor não duplica os dados nem apaga o que foi cadastrado pela API.
popularBanco :: SqlPersistT IO ()
popularBanco = do
  categorias <- count ([] :: [Filter Categoria])
  when (categorias == 0) $ do
    -- Categorias
    processadores <- insert $ Categoria "Processadores" (Just "CPUs para desktop")
    placasVideo   <- insert $ Categoria "Placas de Vídeo" (Just "GPUs para jogos e trabalho")
    memoria       <- insert $ Categoria "Memória RAM" (Just "Módulos DDR4 e DDR5")
    armazenamento <- insert $ Categoria "Armazenamento" (Just "SSDs NVMe e SATA")
    placasMae     <- insert $ Categoria "Placas-mãe" (Just "Placas-mãe AM5 e LGA1700")
    fontes        <- insert $ Categoria "Fontes" (Just "Fontes de alimentação certificadas")

    -- Fabricantes
    amd       <- insert $ Fabricante "AMD" (Just "Estados Unidos") (Just "https://www.amd.com")
    intel     <- insert $ Fabricante "Intel" (Just "Estados Unidos") (Just "https://www.intel.com")
    asus      <- insert $ Fabricante "ASUS" (Just "Taiwan") (Just "https://www.asus.com")
    gigabyte  <- insert $ Fabricante "Gigabyte" (Just "Taiwan") (Just "https://www.gigabyte.com")
    kingston  <- insert $ Fabricante "Kingston" (Just "Estados Unidos") (Just "https://www.kingston.com")
    samsung   <- insert $ Fabricante "Samsung" (Just "Coreia do Sul") (Just "https://www.samsung.com")
    corsair   <- insert $ Fabricante "Corsair" (Just "Estados Unidos") (Just "https://www.corsair.com")

    -- Produtos: nome, descrição, preço, estoque, imagem, categoria, fabricante
    let produto nome desc preco estoque img cat fab =
          insert $ Produto nome desc preco estoque (Just img) cat fab
    ryzen5 <- produto "AMD Ryzen 5 7600" "6 núcleos, 12 threads, até 5.1 GHz, AM5"
                1199.90 25 "/produtos/ryzen-5-7600.jpg" processadores amd
    _ <- produto "AMD Ryzen 7 7800X3D" "8 núcleos, 3D V-Cache, ideal para jogos"
                2599.90 10 "/produtos/ryzen-7-7800x3d.jpg" processadores amd
    _ <- produto "Intel Core i5-14600K" "14 núcleos (6P+8E), até 5.3 GHz, LGA1700"
                1799.90 15 "/produtos/core-i5-14600k.jpg" processadores intel
    rtx4060 <- produto "ASUS Dual GeForce RTX 4060 8GB" "GDDR6, DLSS 3, ray tracing"
                1999.90 12 "/produtos/asus-dual-rtx-4060.jpg" placasVideo asus
    _ <- produto "Gigabyte Radeon RX 7800 XT 16GB" "GDDR6, ótima para 1440p"
                3499.90 6 "/produtos/gigabyte-rx-7800-xt.jpg" placasVideo gigabyte
    _ <- produto "Kingston Fury Beast 32GB (2x16) DDR5" "5600 MHz, CL36"
                749.90 30 "/produtos/kingston-fury-beast-ddr5.jpg" memoria kingston
    _ <- produto "Corsair Vengeance 16GB (2x8) DDR4" "3200 MHz, CL16"
                299.90 40 "/produtos/corsair-vengeance-ddr4.jpg" memoria corsair
    _ <- produto "Samsung 990 PRO 1TB" "SSD NVMe PCIe 4.0, até 7450 MB/s"
                699.90 20 "/produtos/samsung-990-pro.jpg" armazenamento samsung
    _ <- produto "Kingston NV2 500GB" "SSD NVMe PCIe 4.0, até 3500 MB/s"
                249.90 50 "/produtos/kingston-nv2.jpg" armazenamento kingston
    _ <- produto "ASUS TUF Gaming B650-PLUS" "Placa-mãe AM5, DDR5, PCIe 5.0"
                1399.90 8 "/produtos/asus-tuf-b650-plus.jpg" placasMae asus
    _ <- produto "Corsair RM750e" "750W, 80 Plus Gold, modular"
                649.90 18 "/produtos/corsair-rm750e.jpg" fontes corsair

    -- Cliente de demonstração com um endereço (CPF de teste válido)
    cliente <- insert $ Cliente "Cliente Demonstração" "demo@exabyte.com" "12345678909"
                 (Just "(11) 99999-0000")
    _ <- insert $ Endereco cliente "01001-000" "Praça da Sé" "100" Nothing "Sé" "São Paulo" "SP"

    -- Avaliações de exemplo
    agora <- liftIO getCurrentTime
    _ <- insert $ Avaliacao ryzen5 cliente 5 (Just "Ótimo custo-benefício!") agora
    _ <- insert $ Avaliacao rtx4060 cliente 4 (Just "Roda tudo em 1080p.") agora
    return ()
