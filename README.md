# Farever Overlay (mod hlx)

Minimapa, mapa grande e DPS meter para o Farever, desenhados com o motor do
próprio jogo (Heaps `h2d`) via [hlx](https://github.com/hlx-framework/hlx-core). Não usa DirectX nem
`dinput8.dll`.

- **Minimapa** redondo girando com a câmera, com os marcadores de W1 Siagarta
  (incluindo os 8 altares de Soulstone) e outros jogadores por perto.
- **Mapa grande** (F6): arrastar, zoom, clique duplo recentra, filtros na legenda.
- **DPS meter** (F10 mostra/esconde, F9 zera): dano por skill, casts, aba PLAYERS
  com builds e aba HISTORY com lutas passadas.

Instruções de instalação para jogadores: [LEIA-ME.txt](LEIA-ME.txt).

## Compilar

Requer Haxe 4.3.7. Por padrão os scripts usam `../toolchain/haxe`; aponte
`HAXE_TC` para outra instalação se precisar.

```sh
./test.sh      # testes da lógica fora do jogo
./build.sh     # gera build/farever-overlay/
./install.sh   # instala no jogo (com o jogo fechado)
./uninstall.sh
```

As imagens em `data/*.png` (mapa de W1 Siagarta, atlas de ícones, seta do
jogador) vêm dos arquivos do jogo e não estão no repositório. Copie-as da sua
instalação para `data/` antes de rodar o `build.sh`.

## Estrutura

- `src/fo/`: integração com o jogo (hooks, janelas, desenho)
- `src/fo/logic/`: lógica pura (combate, histórico, mapa), coberta por `tests/`
- `vendor/hlx-runtime/`: runtime do hlx (MIT)
- `tools/gen_tables.py`: gera `src/fo/data/GameTables.hx`

Versão anterior em C++ (overlay `dinput8.dll`):
[fareverminimap-cpp](https://github.com/luigiluna/fareverminimap-cpp).

## Licença

MIT. Veja [LICENSE](LICENSE).
