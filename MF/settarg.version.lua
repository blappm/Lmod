local base        = "@PKG@/settarg"
local settarg_cmd = pathJoin(base, "@settarg_cmd@")

prepend_path("PATH",base)
pushenv("LMOD_SETTARG_CMD", settarg_cmd)
set_shell_function("settarg", 'eval $($LMOD_SETTARG_CMD -s sh "$@")',
                              'eval `$LMOD_SETTARG_CMD  -s csh $*`' )

set_shell_function("gettargdir",  'builtin echo $TARG', 'echo $TARG')

local respect = "true"
setenv("SETTARG_TAG1", "OBJ", respect )
setenv("SETTARG_TAG2", "_"  , respect )

if ((os.getenv("LMOD_FULL_SETTARG_SUPPORT") or "no"):lower() ~= "no") then
   set_alias("cdt", "cd $TARG")
   set_shell_function("targ",  'builtin echo $TARG', 'echo $TARG')
   set_shell_function("dbg",   'settarg "$@" dbg',   'settarg $* dbg')
   set_shell_function("empty", 'settarg "$@" empty', 'settarg $* empty')
   set_shell_function("opt",   'settarg "$@" opt',   'settarg $* opt')
   set_shell_function("mdbg",  'settarg "$@" mdbg',  'settarg $* mdbg')
end

local myShell = myShellName()
local exitCmd = "eval `" .. "@path_to_lua@/lua " .. settarg_cmd .. " -s " .. myShell .. " --destroy`"
execute{cmd=exitCmd, modeA = {"unload"}}

local full_support = os.getenv("LMOD_FULL_SETTARG_SUPPORT") or "no"
local TERM         = os.getenv("TERM")

if (full_support ~= "no") then
   if ((myShellName() == "bash" or myShellName() == "zsh" ) and mode() == "load") then
      local startCmd = [==[
        SET_TITLE_BAR=:;

        case "$TERM" in
          xterm*)
            SET_TITLE_BAR=xSetTitleLmod;
            ;;
        esac;

        SHOST=${SHOST-${HOSTNAME%%.*}};
           
        if [ -n "${BASH_VERSION+x}" -a -z ${PROMPT_COMMAND} ]; then
           my_status=1;
        fi;
        if [ -n "${ZSH_VERSION+x}" ]; then
           whence -vf precmd > /dev/null 2>&1;
           my_status=$?;
        fi;
        if [ "${my_status}" -ne 0 ]; then
           precmd()
           {
             eval $(${LMOD_SETTARG_CMD:-:} -s bash);
             ${SET_TITLE_BAR:-:} "${TARG_TITLE_BAR_PAREN}${USER}@${SHOST}:${PWD/#$HOME/~}";
             ${USER_PROMPT_CMD:-:};
           };
        fi;

        # define the PROMPT_COMMAND to be precmd iff it isn't defined already.
        : ${PROMPT_COMMAND:=precmd};
      ]==]
      execute{cmd=startCmd, modeA={"load"}}
   elseif (myShellType() == "csh") then
      set_alias("cwdcmd",'eval `$LMOD_SETTARG_CMD -s csh`')
      set_alias("precmd",'echo -n "\\033]2;${TARG_TITLE_BAR_PAREN}${USER}@${HOST} : $cwd\\007"')
      execute{cmd='echo -n "\\033]2;${USER}@${HOST} : $cwd\\007"',modeA={"unload"}}
   end
end



local helpMsg = [[
The settarg module dynamically and automatically updates "$TARG" and a
host of other environment variables. These new environment variables
encapsulate the state of the modules loaded.

For example, if you have the settarg module and gcc/4.7.2 module loaded
then the following variables are defined in your environment:

   TARG=OBJ/_x86_64_06_1a_gcc-4.7.3
   TARG_COMPILER=gcc-4.7.3
   TARG_COMPILER_FAMILY=gcc
   TARG_MACH=x86_64_06_1a
   TARG_SUMMARY=x86_64_06_1a_gcc-4.7.3

If you change your compiler to intel/13.1.0, these variables change to:

   TARG=OBJ/_x86_64_06_1a_intel-13.1.0
   TARG_COMPILER=intel-13.1.0
   TARG_COMPILER_FAMILY=intel
   TARG_MACH=x86_64_06_1a
   TARG_SUMMARY=x86_64_06_1a_intel-13.1.0

If you then load mpich/3.0.4 module the following variables automatically
change to:

   TARG=OBJ/_x86_64_06_1a_intel-13.1.0_mpich-3.0.4
   TARG_COMPILER=intel-13.1.0
   TARG_COMPILER_FAMILY=intel
   TARG_MACH=x86_64_06_1a
   TARG_MPI=mpich-3.0.4
   TARG_MPI_FAMILY=mpich
   TARG_SUMMARY=x86_64_06_1a_dbg_intel-13.1.0_mpich-3.0.4

You also get some TARG_* variables that always available, independent
of what modules you have loaded:

   TARG_MACH=x86_64_06_1a
   TARG_MACH_DESCRIPT=...
   TARG_HOST=...
   TARG_OS=Linux-3.8.0-27-generic
   TARG_OS_FAMILY=Linux

One way that these variables can be used is part of a build system where
the executables and object files are placed in $TARG.  You can also use
$TARG_COMPILER_FAMILY to know which compiler you are using so that you
can set the appropriate compiler flags.

If the environment variable LMOD_FULL_SETTARG_SUPPORT is set to "yes"
then the settarg module will set the title bar in an xterm terminal.


Settarg can do more.  Please see the Lmod website for more details.
]]

help(helpMsg)
