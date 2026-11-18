" A scratch worksheet lets Vim resolve counts, mappings, modes and motions.
set nomore noswapfile
set shortmess+=I
set ttimeout ttimeoutlen=35
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
  let l:state = [l:mode, line('.'), col('.'), l:command, bufnr() == s:worksheet ? v:true : v:false]
  if l:state !=# s:previous
    let s:previous = l:state
    call s:Emit({'mode': l:mode, 'row': l:state[1], 'column': l:state[2], 'command': l:command, 'worksheet': l:state[4]})
  endif
endfunction

function! Excel(action, ...) abort
  if bufnr() != s:worksheet
    return
  endif
  " Flush a preceding motion before sending an action that uses the selection.
  call s:Report(0)
  call s:Emit({'excelAction': a:action, 'arguments': a:000})
endfunction

if empty(maparg('x', 'n'))
  nnoremap <buffer> x <Cmd>call Excel('delete_cell')<CR>
endif
if empty(maparg('x', 'x'))
  xnoremap <buffer> x <Cmd>call Excel('delete_cell')<CR>
endif

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
