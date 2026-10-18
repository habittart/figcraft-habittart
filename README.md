# FigCraft Habittart

FigCraft ([storytold/figcraft](https://github.com/storytold/figcraft)) com as correções do Marcos,
recompilado automaticamente para macOS (Apple Silicon) e Windows (x64) sempre que sai uma versão
nova do FigCraft ou quando as correções mudam.

## Correções (`patches/habittart.patch`)

- **Cores no macOS:** as janelas passam a ser marcadas como sRGB, então o macOS converte as cores
  para a tela (igual ao Figma). Antes, numa tela Display P3, tudo ficava mais saturado.
- **Adobe Fonts:** as fontes ativadas pelo Creative Cloud (pasta escondida `livetype`) passam a
  aparecer no FigCraft, no macOS e no Windows.
- **Importação de `.fig`:** o ajuste de saturação das imagens do Figma (salvo como `vibrance`) é
  importado; fotos em preto e branco continuam em preto e branco.
- **Um app só:** uma segunda abertura entrega arquivos e links ao FigCraft que já está aberto, e as
  configurações gerais (`settings/`) valem nos dois computadores.
- **Tudo online sozinho:** com o endereço do servidor e a chave (`habittart-servidor.txt` na pasta de
  configurações, copiado pelo atualizador), o FigCraft abre ao iniciar todos os projetos do servidor,
  abre os que aparecerem depois (feitos no outro computador) e publica cada documento novo que não
  estiver online. A chave nunca vai para este repositório.
- **MCP em segundo plano:** os comandos do canal de controle (MCP) funcionam com o FigCraft atrás
  de outras janelas ou minimizado.

## Proxy do MCP (`proxy/`)

Fica entre o app do Claude e o `figcraft-cli mcp --attach 7979`: o MCP sobe mesmo com o FigCraft
fechado, abre o FigCraft com o canal de controle quando precisa e reconecta se o app reiniciar.

## Instalar e manter atualizado

- **Mac (Terminal):**
  `curl -fsSL https://raw.githubusercontent.com/habittart/figcraft-habittart/main/scripts/mac/atualizar-figcraft.command | bash`
- **Windows (PowerShell):**
  `irm https://raw.githubusercontent.com/habittart/figcraft-habittart/main/scripts/windows/atualizar-figcraft.ps1 | iex`

Depois da primeira vez, cada computador verifica sozinho (no login e a cada 6 horas) e instala a
versão corrigida mais recente. Se o FigCraft oficial for atualizado por cima, a verificação
percebe e reinstala a versão corrigida.

## Se a compilação falhar

Uma versão nova do FigCraft pode mudar o código que as correções alteram. A action `build` falha,
os computadores continuam na última versão boa, e o patch precisa ser ajustado.
