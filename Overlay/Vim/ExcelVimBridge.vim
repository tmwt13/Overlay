" A scratch worksheet lets Vim resolve counts, mappings, modes and motions.
set nomore noswapfile
set shortmess+=I
set ttimeout ttimeoutlen=35
set viminfo='0,<100,s64
if $EXCEL_VIM_PERSIST_REGISTERS ==# '1'
  silent! rviminfo!
endif
enew!
setlocal buftype=nofile bufhidden=wipe nowrap nospell nolist
setlocal undolevels=-1
call setline(1, repeat([repeat('x', 1024)], 2048))
call cursor(1024, 512)
setlocal nomodified

let s:worksheet = bufnr()
let s:row = repeat('x', 1024)
let s:tick = b:changedtick
let s:previous = []
function! s:Emit(message) abort
  call writefile([json_encode(a:message)], $EXCEL_VIM_EVENTS, 'a')
endfunction

function! s:Report(timer) abort
  let l:mode = mode(1)
  if bufnr() == s:worksheet && l:mode ==# 'n' && b:changedtick != s:tick
    let l:position = empty(s:previous) ? [1024, 512] : s:previous[1:2]
    silent keepjumps %delete _
    call setline(1, repeat([s:row], 2048))
    call cursor(l:position[0], l:position[1])
    let s:tick = b:changedtick
  endif
  let l:command = getcmdtype() ==# ':' ? getcmdline() : v:null
  let l:state = [l:mode, line('.'), col('.'), l:command, bufnr() == s:worksheet ? v:true : v:false, reg_recording()]
  if l:state !=# s:previous
    if $EXCEL_VIM_PERSIST_REGISTERS ==# '1' && !empty(s:previous) && !empty(s:previous[5]) && empty(l:state[5])
      silent! wviminfo!
    endif
    let s:previous = l:state
    call s:Emit({'mode': l:mode, 'row': l:state[1], 'column': l:state[2], 'command': l:command, 'worksheet': l:state[4], 'recordingRegister': empty(l:state[5]) ? v:null : l:state[5]})
  endif
endfunction

let s:mirroringExcel = 0
let s:forwardedInsert = 0
let s:insertOrigin = []

function! s:SetExcelMirror(active) abort
  let s:mirroringExcel = a:active
endfunction

function! s:ForwardInsert(kind, text) abort
  if !s:mirroringExcel || !empty(reg_executing())
    let s:forwardedInsert = 1
    call s:Emit({'insertInput': a:kind, 'insertText': a:text})
  endif
endfunction

function! s:InsertCharacter() abort
  call s:ForwardInsert('text', v:char)
  let v:char = ''
endfunction

function! s:EndInsert() abort
  " Vim normally backs up a column on Escape. Excel's insertion point is separate.
  if !empty(s:insertOrigin)
    call setpos('.', s:insertOrigin)
  endif
  if s:forwardedInsert
    call s:Emit({'insertInput': 'commit'})
  endif
  let s:forwardedInsert = 0
  let s:mirroringExcel = 0
endfunction

augroup ExcelWorksheetInsert
  autocmd!
  autocmd InsertEnter <buffer> let s:insertOrigin = getpos('.')
  autocmd InsertCharPre <buffer> call <SID>InsertCharacter()
  autocmd InsertLeave <buffer> call <SID>EndInsert()
augroup END

" The PTY uses these private sequences to mark input Excel already received.
execute "set <F23>=\e[97~"
execute "set <F24>=\e[98~"
inoremap <buffer> <F23> <Cmd>call <SID>SetExcelMirror(1)<CR>
inoremap <buffer> <F24> <Cmd>call <SID>SetExcelMirror(0)<CR>
inoremap <buffer> <Tab> <Cmd>call <SID>ForwardInsert('tab', '')<CR>
inoremap <buffer> <S-Tab> <Cmd>call <SID>ForwardInsert('backTab', '')<CR>
inoremap <buffer> <CR> <Cmd>call <SID>ForwardInsert('return', '')<CR>
inoremap <buffer> <BS> <Cmd>call <SID>ForwardInsert('backspace', '')<CR>

" Excel insert mode starts in the active cell, even for Vim's uppercase I.
if empty(maparg('I', 'n'))
  nnoremap <buffer> I i
endif

if empty(maparg('=', 'n'))
  nnoremap <buffer> = i=
endif

function! Excel(action, ...) abort
  if bufnr() != s:worksheet
    return
  endif
  " Flush a preceding motion before sending an action that uses the selection.
  call s:Report(0)
  call s:Emit({'excelAction': a:action, 'arguments': a:000})
endfunction

if empty(maparg('c', 'n'))
  nnoremap <buffer> c <Cmd>call Excel('delete_cell')<CR>i
endif

if empty(maparg('x', 'n'))
  nnoremap <buffer> x <Cmd>call Excel('delete_cell')<CR>
endif
if empty(maparg('x', 'x'))
  xnoremap <buffer> x <Cmd>call Excel('delete_cell')<CR>
endif

if empty(maparg('y', 'n'))
  nnoremap <buffer> y <Cmd>call Excel('copy')<CR>
endif
if empty(maparg('p', 'n'))
  nnoremap <buffer> p <Cmd>call Excel('paste')<CR>
endif

for [s:key, s:direction] in [['h', 'left'], ['l', 'right'], ['j', 'down'], ['k', 'up'],
      \ ['<Left>', 'left'], ['<Right>', 'right'], ['<Down>', 'down'], ['<Up>', 'up']]
  for s:mode in ['n', 'x']
    if empty(maparg(s:key, s:mode))
      execute s:mode . 'noremap <buffer> ' . s:key . ' <Cmd>call Excel("cell_step", "' . s:direction . '", string(v:count1))<CR>'
    endif
  endfor
endfor

for s:mode in ['n', 'x']
  if empty(maparg('gg', s:mode))
    execute s:mode . 'noremap <buffer> gg <Cmd>call Excel("cell_row", string(v:count1))<CR>'
  endif
  if empty(maparg('G', s:mode))
    execute s:mode . 'noremap <buffer> G <Cmd>call Excel("cell_row", string(v:count))<CR>'
  endif
endfor

for [s:key, s:direction] in [['w', 'forward'], ['b', 'backward']]
  for s:mode in ['n', 'x']
    if empty(maparg(s:key, s:mode))
      execute s:mode . 'noremap <buffer> ' . s:key . ' <Cmd>call Excel("cell_jump", "' . s:direction . '", string(v:count1))<CR>'
    endif
  endfor
endfor

let s:commands = split($EXCEL_VIM_COMMANDS, ',')

function! s:AcceptCommand() abort
  let l:input = substitute(getcmdline(), "^'<,'>", '', '')
  let l:name = matchstr(l:input, '^\s*\zs[^[:space:](]\+')
  let l:name = tolower(l:name)
  if l:name ==# 'help' && l:input !~? '^\s*help\s\+excel\s*$'
    return "\<CR>"
  endif
  if getcmdtype() ==# ':' && index(s:commands, l:name) >= 0
    call s:Emit({'excelCommand': l:input})
    return "\<C-C>"
  endif
  return "\<CR>"
endfunction

" Excel commands go back to the host. Vim handles all other Ex commands.
cnoremap <expr> <CR> <SID>AcceptCommand()
call timer_start(10, function('<SID>Report'), {'repeat': -1})
call <SID>Report(0)

" remapping of basic functions
nnoremap u <Cmd>call Excel('undo')<CR>
nnoremap <C-r> <Cmd>call Excel('redo')<CR>
