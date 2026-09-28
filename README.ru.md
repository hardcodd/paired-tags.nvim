# paired-tags.nvim: парные теги и блоки шаблонов в Neovim

Плагин автоматически закрывает теги, синхронно переименовывает парные имена
и подсвечивает пару под курсором. Поддерживаются HTML, HTML-шаблоны Django и
Jinja, XML, JSX/TSX, Vue, Svelte и HTML внутри Markdown. В шаблонах Django и
Jinja плагин также работает с парными управляющими блоками.

![Предпросмотр paired-tags.nvim с парой JSX-тегов](assets/social-preview.png)

## Возможности

| Действие | Результат |
| --- | --- |
| Набрать `<section>` | Появится `</section>`, курсор останется между тегами. |
| Переименовать один из тегов `<section>...</section>` | Имя второго тега изменится вместе с ним. |
| Поставить курсор на парный тег | Подсветятся оба имени. |
| Нажать Enter между `<section>` и `</section>` | Появится строка с отступом, закрывающий тег останется на уровне открывающего. |
| Набрать `{%if active%}` в Django или Jinja | Получится `{% if active %}{% endif %}`. |
| Переименовать ключевое слово парного блока | Изменится соответствующее слово во втором операторе. |
| Поставить курсор на `{% else %}` | Подсветятся `else` и управляющий им `if` или `for`. |
| Набрать `{%`, `{{` или `{#` в шаблоне | Получится `{%  %}`, `{{  }}` или `{#  #}`, курсор окажется между пробелами. |

Поддерживаются файловые типы `html`, `htmldjango`, `jinja`, `jinja2`, `xml`,
`javascriptreact`, `typescriptreact`, `vue`, `svelte` и HTML внутри `markdown`.
Плагин использует Tree-sitter и не устанавливает парсеры самостоятельно.

### HTML и другие теги

Закрывающий тег добавляется после завершённого открывающего тега. Уже
существующий закрывающий тег сохраняется; для самозакрывающихся тегов и
пустых HTML-элементов новый тег не создаётся. Плагин учитывает кавычки в
атрибутах, вложенные теги, JSX-компоненты и фрагменты. Строки, комментарии,
блоки кода Markdown и другие области без разметки остаются нетронутыми.

При переименовании меняются только имена парных тегов, в том числе при
редактировании закрывающего тега, многострочного открывающего тега и
временном нарушении синтаксиса. Подсветка работает для явно определённой
парсером пары и исчезает, когда курсор покидает тег. Если пару нельзя
определить надёжно, плагин не меняет соседние элементы.

Enter между соседними HTML-тегами создаёт строку с отступом по действующим
настройкам буфера (`shiftwidth`, `expandtab`, `tabstop`), включая настройки
EditorConfig. Это действие доступно в `html`, `htmldjango`, `jinja`, `jinja2`.

### Шаблоны Django и Jinja

HTML-теги внутри `htmldjango`, `jinja` и `jinja2` поддерживают автозакрытие,
переименование, подсветку и Enter. Синтаксис `{% ... %}`, `{{ ... }}` и
`{# ... #}`, а также тела Django `{% verbatim %}` и Jinja `{% raw %}`
не обрабатываются как HTML. Теги в разных ветках шаблона не считаются
безопасной парой.

После завершающего `}` у открывающего блока вставляется соответствующий
`{% end... %}`. Можно переименовать любой из двух операторов, подсветить
пару или создать строку с отступом между соседними операторами. Django:
`if`, `for`, `block`, `comment`, `verbatim`, `autoescape`, `filter`, `with`,
`spaceless`, `ifchanged`, `blocktrans`/`blocktranslate`. Jinja: `if`, `for`,
`block`, `macro`, `call`, `filter`, блочный `set`, `with`, `autoescape`,
`trans`, `raw`. Поддерживаются разделители Jinja с управлением пробелами.
Одиночные операторы вроде `include` не получают закрывающую пару.
Если курсор стоит на ключевом слове ветки, подсвечиваются оно и открывающий
оператор его блока: в Django — `elif`/`else` у `if`, `empty` у `for`, `else`
у `ifchanged` и `plural` у `blocktrans`/`blocktranslate`; в Jinja —
`elif`/`else` у `if` и `else` у `for`. Вложенная ветка связывается с
ближайшим своим блоком.
Синхронное переименование по-прежнему касается только открывающего и
закрывающего операторов.

При вводе `{%`, `{{` или `{#` добавляется соответствующий закрывающий
разделитель и по одному пробелу с каждой стороны курсора; содержимое вводи
без дополнительных пробелов. Ввод закрывающих символов переводит курсор
через автоматически добавленную пару. Уже стоящий
рядом закрывающий разделитель сохраняется. Если `nvim-autopairs` вставил `}`,
плагин использует её без лишней скобки. Выражения и комментарии не создают управляющий блок.
В строках, комментариях и телах raw/verbatim разделители остаются обычным
текстом.

## Требования

- Проверенная версия — Neovim 0.12.5. Более старые версии не проверялись.
- Тесты шаблонов использовали ревизии грамматик `htmldjango` `a1031889` и
  `jinja` / `jinja_inline` `c213d374`. Другие ревизии не проверялись.
- Установленные Tree-sitter-парсеры: `html`; `htmldjango` и `html` для
  Django; `jinja`, `jinja_inline` и `html` для Jinja; `xml`; `javascript`
  для `javascriptreact`; `tsx` для `typescriptreact`; `vue`; `svelte`;
  `markdown` и `html` для HTML в Markdown. `nvim-treesitter` может установить
  эти парсеры, но не является зависимостью плагина во время работы.

Если парсер недоступен, зависящие от него автозакрытие, переименование,
дополнение разделителей и подсветка не меняют буфер. HTML Enter не требует
парсера; Enter для блоков шаблона требует его.

## Установка и настройка

Через [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "hardcodd/paired-tags.nvim",
  main = "paired_tags",
  opts = {},
  lazy = false,
}
```

При другом менеджере добавь репозиторий в `runtimepath` и вызови
`require("paired_tags").setup()`. Настройка добавляет Insert-сочетания `>`,
`{`, `%`, `#`, `-`, `}` и `<CR>`, обработчики изменений и курсора, а также
обработчик вставки.
Повторный вызов `setup()` не дублирует их. Если другой плагин перехватывает
`<CR>`, отключи у него это сочетание; например, у `nvim-autopairs` можно
установить `map_cr = false`. Сочетания `{` и `}` работают при любом порядке
загрузки этих плагинов, сохраняя обычное дополнение скобок `nvim-autopairs`.

По умолчанию используются группы `PairedTagsOpening` и `PairedTagsClosing`,
связанные с `MatchParen`. Их можно заменить при первом вызове:

```lua
require("paired_tags").setup({
  highlight = { opening = "Search", closing = "Search" },
})
```

Имя каждой группы задаётся отдельно. Некорректные параметры вызывают ошибку.

## Ограничения и планы

PHP-шаблоны пока не поддерживаются. Остальные планы перечислены в
[ROADMAP.ru.md](ROADMAP.ru.md). При отсутствии парсера или однозначной пары
плагин пропускает изменение. Он не форматирует документ и не дополняет
кавычки или скобки в общем случае.

## Проверка

Из корня репозитория, при установленных перечисленных парсерах:

```sh
nvim --headless -u NONE -i NONE -n \
  '+luafile tests/bootstrap.lua' \
  '+lua local ok, err = pcall(dofile, "tests/template_blocks_spec.lua"); if not ok then print(err); vim.cmd("cquit") end' \
  +qa!
```

Замени путь на `template_html_spec.lua`, `template_branches_spec.lua`,
`template_delimiters_spec.lua`, `setup_spec.lua`,
`html_enter_spec.lua`, `highlight_spec.lua`, `paired_editing_spec.lua`,
`rename_fast_path_spec.lua`, `tag_scenarios_spec.lua` или один из
`tag_bug*_spec.lua`, чтобы выполнить остальные наборы. Для парсеров вне
стандартного каталога Neovim задай `PAIRED_TAGS_PARSER_RTP` с каталогом
парсеров и соответствующих запросов. Если парсеры Jinja стоят отдельно,
добавь их каталог в `runtimepath` после `tests/bootstrap.lua`. Тест
`highlight_config_spec.lua` запускается без `tests/bootstrap.lua`, чтобы
проверить пользовательские настройки до первого `setup()`.
Для проверки обоих порядков загрузки замени путь на каталог установленного
`nvim-autopairs`:

```sh
PAIRED_TAGS_AUTOPAIRS_RTP=/path/to/nvim-autopairs \
  nvim --headless -u NONE -i NONE -n \
  '+luafile tests/bootstrap.lua' \
  '+lua local ok, err = pcall(dofile, "tests/template_delimiter_autopairs_spec.lua"); if not ok then print(err); vim.cmd("cquit") end' \
  +qa!

PAIRED_TAGS_AUTOPAIRS_RTP=/path/to/nvim-autopairs \
  nvim --headless -u NONE -i NONE -n \
  '+lua vim.opt.rtp:append(vim.env.PAIRED_TAGS_AUTOPAIRS_RTP); require("nvim-autopairs").setup({ map_cr = false })' \
  '+luafile tests/bootstrap.lua' \
  '+lua local ok, err = pcall(dofile, "tests/template_delimiter_autopairs_spec.lua"); if not ok then print(err); vim.cmd("cquit") end' \
  +qa!
```

Совместная работа проверена с `nvim-autopairs` 0.10.0 (`23320e7`).

Контракт поведения — в [SPECS.md](SPECS.md).

## Лицензия

[MIT](LICENSE).
