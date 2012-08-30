require("strict")
_ModuleTable_      = ""
local DfltModPath  = DfltModPath
local Master       = Master
local ModulePath   = ModulePath
local Purge        = Purge
local assert       = assert
local concatTbl    = table.concat
local expert       = expert
local getenv       = os.getenv
local ignoreT      = { ['.'] =1, ['..'] = 1, CVS=1, ['.git'] = 1, ['.svn']=1,
                       ['.hg']= 1, ['.bzr'] = 1,}
local io           = io
local ipairs       = ipairs
local loadstring   = loadstring
local max          = math.max
local next         = next
local os           = os
local pairs        = pairs
local prtErr       = prtErr
local setmetatable = setmetatable
local string       = string
local systemG      = _G
local tostring     = tostring
local type         = type
local unpack       = unpack
local varTbl       = varTbl

require("string_split")
require("fileOps")
require("serializeTbl")

local Var          = require('Var')
local lfs          = require('lfs')
local pathJoin     = pathJoin
local Dbg          = require('Dbg')
local ColumnTable  = require('ColumnTable')
local posix        = require("posix")


--module("MT")
local M = {}

function M.name(self)
   return '_ModuleTable_'
end

s_loadOrder = 0
s_mt = nil

local function build_locationTbl(tbl, pathA)
   local dbg = Dbg:dbg()
   for _,path in ipairs(pathA)  do
      local attr = lfs.attributes(path)
      if ( attr and attr.mode == "directory") then
         for file in lfs.dir(path) do
            local f = pathJoin(path,file)
            local readable = posix.access(f,"r")
            if (readable and not ignoreT[file]) then
               local a   = tbl[file] or {}
               file      = file:gsub("%.lua$","")
               a[#a+1]   = {file = f, mpath = path }
               tbl[file] = a
            end
         end
      end
   end
end


local function new(self, s)
   local dbg  = Dbg:dbg()
   dbg.start("MT:new()")
   local o            = {}

   o.mT               = {}
   o.version          = 2
   o.family           = {}
   o.mpathA           = {}
   o.baseMpathA       = {}
   o._same            = true
   o._MPATH           = ""
   o._locationTbl     = {}

   o._changePATH      = false
   o._changePATHCount = 0

   setmetatable(o,self)
   self.__index = self

   local active, total

   if (not s) then
      local v             =  getenv(ModulePath)
      varTbl[DfltModPath] = Var:new(DfltModPath, v)
      o:buildBaseMpathA(v)
      dbg.print("Initializing ", DfltModPath, ":", v, "\n")
   else
      assert(loadstring(s))()
      local _ModuleTable_ = systemG._ModuleTable_

      if (_ModuleTable_.version == 1) then
         s_loadOrder = self:convertMT(_ModuleTable_)
      else
         for k,v in pairs(_ModuleTable_) do
            o[k] = v
         end
         s_loadOrder = o.activeSize
      end
      o._MPATH = concatTbl(o.mpathA,":")
      varTbl[DfltModPath] = Var:new(DfltModPath, concatTbl(o.baseMpathA,":"))
   end

   -- I don't think I need this

   --if (active and active.Loaded) then
   --   local mTypeA = active.mType or {}
   --   for i,v in ipairs(active.Loaded) do
   --      local hashV = nil
   --      if (active.hash) then
   --         hashV = active.hash[i]
   --      end
   --      local mType = mTypeA[i] or "mw"
   --      local t = { fn = active.FN[i], modFullName = active.fullModName[i],
   --                 default = active.default[i], hash = hashV, modName=v,
   --                 mType = mType, }
   --      o:addActive(t)
   --   end
   --   mTypeA = total.mType or {}
   --   for i,v in ipairs(total.Loaded) do
   --      local mType = mTypeA[i] or "mw"
   --      local t = { fn = total.FN[i], modFullName = total.fullModName[i],
   --                  default = total.default[i], modName=v, mType = mType, }
   --      o:addTotal(t)
   --   end
   --end

   o._inactive        = o.inactive or {}
   o.inactive         = {}

   dbg.fini()
   return o
end

function M.convertMT(self, v1)
   local active = v1.active
   local a      = active.Loaded
   local sz     = #a
   for i = 1, sz do
      local sn = a[i]
      local t  = { fn = active.FN[i], modFullName = active.fullModName[i],
                   default = active.default[i], hash = active.hash[i], modName = sn,
                   mTypeA  = active.mTypeA[i]
      }
      self.add(t,"active")
   end

   aa          = {}
   local total = v1.total
   a           = total.Loaded
   for i = 1, #a do
      local sn = a[i]
      if (not self:have(sn,"active")) then
         local t = { modFullName = total.fullModName[i], modName = sn }
         self.add(t,"inactive")
         aa[#aa+1] = sn
      end
   end
   
   self.inactive   = aa
   self.__inactive = aa

   return sz   -- Return the new loadOrder number.
end
   


local function setupMPATH(self,mpath)
   self._same = self:sameMPATH(mpath)
   if (not self._same) then
      self:buildMpathA(mpath)
   end
   build_locationTbl(self._locationTbl,self.mpathA)
end

function M.mt(self)
   if (s_mt == nil) then
      local dbg  = Dbg:dbg()
      dbg.start("mt()")
      local shell        = systemG.Master:master().shell
      s_mt               = new(self, shell:getMT())
      varTbl[ModulePath] = Var:new(ModulePath)
      setupMPATH(s_mt, varTbl[ModulePath]:expand())
      if (not s_mt._same) then
         s_mt:reloadAllModules()
      end
      dbg.fini()
   end
   return s_mt
end

function M.getMTfromFile(self,fn)
   local dbg  = Dbg:dbg()
   dbg.start("mt:getMTfromFile(",fn,")")
   local f = io.open(fn,"r")
   if (not f) then
      io.stdout:write("false\n")
      os.exit(1)
   end
   local s = f:read("*all")
   f:close()

   -----------------------------------------------
   -- Initialize MT with file: fn
   -- Save module name in hash table "t"
   -- with Hash Sum as value

   local l_mt   = new(self, s)
   local mpath  = l_mt._MPATH
   local t      = {}
   local a      = {}  -- list of "worker-bee" modules
   local m      = {}  -- list of "manager"    modules

   local active = l_mt:list("short","active")

   for i = 1,#active do
      local sn    = active[i]
      t[sn]       = l_mt:getHash(sn)
      local mType = l_mt:mType(sn)
      if (mType == "w") then
         a[#a+1] = v
      else
         m[#m+1] = v
      end
   end
   
   varTbl[ModulePath] = Var:new(ModulePath,mpath)
   dbg.print("(1) varTbl[ModulePath]:expand(): ",varTbl[ModulePath]:expand(),"\n")
   Purge()
   mpath = varTbl[ModulePath]:expand()
   dbg.print("(2) varTbl[ModulePath]:expand(): ",mpath,"\n")

   -----------------------------------------------------------
   -- Clear MT and load modules from saved modules stored in
   -- "t" from above.
   local baseMPATH = concatTbl(self.baseMpathA,":")
   s_mt = new(self,nil)
   posix.setenv(self:name(),"",true)
   setupMPATH(s_mt, mpath)
   s_mt:buildBaseMpathA(baseMPATH)
   varTbl[DfltModPath] = Var:new(DfltModPath,baseMPATH)

   dbg.print("(3) varTbl[ModulePath]:expand(): ",varTbl[ModulePath]:expand(),"\n")
   local mcp_old = mcp
   mcp           = MCP
   mcp:load(unpack(a))
   mcp           = mcp_old

   local master = systemG.Master:master()

   master.fakeload(unpack(m))
   

   s_mt:assignHashSum()
   a = {}
   for k in pairs(t) do
      if(t[v] ~= s_mt:getHash(k)) then
         a[#a + 1] = k
      end
   end

   if (#a > 0) then
      LmodError("The following modules have changed: ", concatTbl(a," "),"\n",
            "Please reset this default setup\n")
   end

   local n = "__LMOD_DEFAULT_MODULES_LOADED__"
   varTbl[n] = Var:new(n)
   varTbl[n]:set("1")
   dbg.print("baseMpathA: ",concatTbl(self.baseMpathA,":"),"\n")

   dbg.fini()
end
   
function M.changePATH(self)
   if (not self._changePATH) then
      assert(self._changePATHCount == 0)
      self._changePATHCount = self._changePATHCount + 1
   end
   self._changePATH = true
end

function M.beginOP(self)
   if (self._changePATH == true) then
      self._changePATHCount = self._changePATHCount + 1
   end
end

function M.endOP(self)
   if (self._changePATH == true) then
      self._changePATHCount = max(self._changePATHCount - 1, 0)
   end
end

function M.safeToCheckZombies(self)
   local result = self._changePATHCount == 0 and self._changePATH
   local s      = "nil"
   if (result) then  s = "true" end
   if (self._changePATHCount == 0) then
      self._changePATH = false
   end
   return result
end

function M.setfamily(self,familyNm,mName)
   local results = self.family[familyNm]
   self.family[familyNm] = mName
   local n = "LMOD_FAMILY_" .. familyNm:upper()
   MCP:setenv(n, mName)
   n = "TACC_FAMILY_" .. familyNm:upper()
   MCP:setenv(n, mName)
   return results
end

function M.unsetfamily(self,familyNm)
   local n = "LMOD_FAMILY_" .. familyNm:upper()
   MCP:unsetenv(n, "")
   n = "TACC_FAMILY_" .. familyNm:upper()
   MCP:unsetenv(n, "")
   self.family[familyNm] = nil
end

function M.getfamily(self,familyNm)
   if (familyNm == nil) then
      return self.family
   end
   return self.family[familyNm]
end


function M.locationTbl(self, fn)
   return self._locationTbl[fn]
end

function M.sameMPATH(self, mpath)
   return self._MPATH == mpath
end

function M.module_pathA(self)
   return self.mpathA
end

function M.buildMpathA(self, mpath)
   local mpathA = {}
   for path in mpath:split(":") do
      mpathA[#mpathA + 1] = path
   end
   self.mpathA = mpathA
   self._MPATH = concatTbl(mpathA,":")
end

function M.buildBaseMpathA(self, mpath)
   local mpathA = {}
   mpath = mpath or ""
   for path in mpath:split(":") do
      mpathA[#mpathA + 1] = path
   end
   self.baseMpathA = mpathA
end


function M.getBaseMPATH(self)
   return concatTbl(self.baseMpathA,":")
end

function M.reEvalModulePath(self)
   self:buildMpathA(varTbl[ModulePath]:expand())
   self._locationTbl = {}
   build_locationTbl(self._locationTbl, self.mpathA)
end

function M.reloadAllModules(self)
   local dbg    = Dbg:dbg()
   local master = systemG.Master:master()
   local count  = 0
   local ncount = 5

   local changed = false
   local done    = false
   while (not done) do
      local same  = master:reloadAll()
      if (not same) then
         changed = true
      end
      count       = count + 1
      if (count > ncount) then
         LmodError("ReLoading more than ", ncount, " times-> exiting\n")
      end
      done = self:sameMPATH(varTbl[ModulePath]:expand())
   end

   local safe = master:safeToUpdate()
   if (not safe and changed) then
      LmodError("MODULEPATH has changed: run \"module update\" to repair\n")
   end
   return not changed
end


------------------------------------------------------------
-- Pass-Thru function modules in the Active list

local function shortName(moduleName)
   return moduleName:gsub("([^/]+)/.*","%1")
end

function M.add(self, t, status)
   local mT = self.mT
   s_loadOrder = s_loadOrder + 1
   mT[t.modName] = { fullName  = t.modFullName,
                     short     = t.modName,
                     FN        = t.fn,
                     default   = t.default,
                     mType     = t.mType,
                     hash      = t.hash,
                     status    = status,
                     loadOrder = s_loadOrder,
   }
end

function M.fileName(self, moduleName)
   local mT = self.mT
   local sn = shortName(moduleName)
   return mT[sn].FN
end

function M.setStatus(self, moduleName, status)
   local mT = self.mT
   local sn = shortName(moduleName)
   mT[sn].status = status
end

function M.have(self, moduleName, status)
   local mT = self.mT
   local sn = shortName(moduleName)
   local entry = mT[sn]
   if (entry == nil) then
      return false
   end
   return ((status == "any") or (status == entry.status))
end

function M.list(self, kind, status)
   local mT   = self.mT
   local icnt = 0
   local a    = {}
   local b    = {}

   for k,v in pairs(mT) do
      if (status == "any" or status == v.status) then
         icnt = icnt + 1
         a[icnt] = { v[kind], v.loadOrder}
      end
   end

   table.sort (a, function(x,y) return x[2] < y[2] end)

   for i = 1, icnt do
      b[i] = a[i][1]
   end
   return b
end

function M.setHash(self)
   local mT   = self.mT

   for k,v in pairs(mT) do
      if (v.status == "active") then
         local s    = capture(pathJoin(cmdDir(),"computeHashSum").. " " .. v.FN)
         v.hash     = s:sub(1,-2)
      end
   end
end

function M.getHash(self)
   local mT  = self.mT
   local sn  = shortName(moduleName)
   return mT[sn].hash
end

function M.markDefault(self, moduleName)
   local mT = self.mT
   local sn = shortName(moduleName)
   mT[sn].default = 1
end

function M.default(self, moduleName)
   local mT = self.mT
   local sn = shortName(moduleName)
   return mT[sn].default
end

function M.setLoadOrder(self)
   local a  = self:list("short","active")
   local mT = self.mT
   local sz = #a

   for i = 1,sz do
      local sn = a[i]
      mT[sn].loadOrder = i
   end      
   return sz
end

function M.fullName(self,moduleName)
   local mT = self.mT
   local sn = shortName(moduleName)
   return mT[sn].fullName
end

function M.mType(self,moduleName)
   local mT = self.mT
   local sn = shortName(moduleName)
   return mT[sn].mType
end

function M.remove(self, moduleName)
   local mT = self.mT
   local sn = shortName(moduleName)
   mT[sn] = nil
end

function M.safeToSave(self)
   local mT = self.mT
   local a  = {}
   for k,v in pairs(mT) do
      if (v.status == "active" and v.mType == "mw") then
         a[#a+1] = k
      end
   end
   return a
end

local function bool(a)
   local result = "false"
   if (a) then result = "true" end
   return result
end


function M.changeInactive(self)
   local master = systemG.Master:master()
   local t      = {}
   local aa     = self._inactive

   local prt    = not expert()
   local ct 

   ------------------------------------------------------------
   -- print out newly activated Modules

   local i = 0
   for _,v in ipairs(aa) do
      if (self:have(v,"active")) then
         local fullName = self:fullName(v)
         i    = i + 1
         t[i] = '  ' .. i .. ') ' .. fullName
         master:reloadClear(fullName)
      end
   end
   if (i > 0 and prt) then
      io.stderr:write("Activating Modules:\n")
      ct = ColumnTable:new{tbl=t, prt=prtErr}
      ct:print_tbl()
      t = {}
   end

   ------------------------------------------------------------
   -- Form new inactive list
   aa = {}
   local mT = self.mT
   for k,v in pairs(mT) do
      if (v.status ~= "active") then
         t[k]      = 1
         aa[#aa+1] = v
      end
   end

   self.inactive = aa
   local same = (#aa == #self._inactive)
   if (same) then
      for _,v in ipairs(self._inactive) do
         if (not t[v]) then
            same = false
            break
         end
      end
   end

   if (not same and #aa > 0 and prt) then
      t = {}
      for i,v in ipairs(aa) do
         t[#t + 1] = '  ' .. i .. ') ' .. v
      end
      io.stderr:write("Inactive Modules:\n")
      ct = ColumnTable:new{tbl=t, prt=prtErr}
      ct:print_tbl()
   end

   return same
end


function M.serializeTbl(self)
   
   s_mt.activeSize = self:setLoadOrder()

   local s = _G.serializeTbl{ indent=false, name=self.name(), value=s_mt}
   return s:gsub("[ \n]","")
end

return M
