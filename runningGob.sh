#!/bin/bash
make
#make install

# set options and file for apron execution
options_apron="--set ana.activated[+] apron --enable ana.int.interval --set ana.apron.domain polyhedra --enable warn.debug" #note: preprocessing first needs to be added to apron
options_signs="--set "ana.activated[+]" signs --enable warn.debug" 
options_term="--set "ana.activated[+]" termination --enable warn.debug" 

cfile_loops="tests/regression/55-loop-unrolling/01-simple-cases.c"      
cfile_signs="tests/regression/99-tutorials/01-first.c"

# run analysis, write cil output to file and enable visualization via html
#./goblint $cfile_loops $options_apron --enable justcil > output.txt
#./goblint $cfile_loops $options_apron --html 

# run analysis, write cil output to file and enable visualization via html
./goblint $cfile_loops $options_term --enable justcil > output.txt
./goblint $cfile_loops $options_term --html 

# set up server to see visualizatino
python3 -m http.server --directory result 8081
#./goblint --enable dbg.debug tests/regression/55-loop-unrolling/01-simple-cases.c --enable ana.int.interval --set "ana.activated[+]" signs --enable justcil > output.txt

