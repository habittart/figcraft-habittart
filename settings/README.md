# Configuracoes gerais compartilhadas

`figcraft-settings.json` vale para o FigCraft do Mac e do PC. Os atualizadores copiam este arquivo
para a pasta de configuracoes do FigCraft, e o app aplica as chaves daqui sempre que o arquivo muda
(as outras ficam como estao em cada computador). Nomes das chaves: os campos de `Prefs` em
`crates/engine/src/lib.rs` do FigCraft (por exemplo `theme`, `nudge_small`, `nudge_big`,
`keep_tool`, `show_dimensions`, `language`, `user_name`, `publish_server`).

Nunca coloque links de edicao, chaves ou tokens aqui: o repositorio e publico.
