; Assembled to build\myhits_tables.bin: the game's tables as a file. A game
; started with --watch takes them from it whenever it changes, so a number
; changed in tables.inc is on the screen a second after this is assembled
; again, which tools\watch.ps1 does whenever tables.inc is saved.
;
; The game takes the file only if its names are the names it was built with:
; see `table_image` in ..\common\tables.inc.
include '..\common\shared.inc'
include 'build\myhits_art.inc'
include 'tables.inc'
include 'tables_image.inc'
