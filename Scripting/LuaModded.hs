{-# LANGUAGE ForeignFunctionInterface, TypeSynonymInstances, FlexibleInstances #-}
-- |
-- Module      : Scripting.Lua
-- Copyright   : (c) Gracjan Polak 2007
--
-- License     : BSD3-style
--
-- Maintainer  : gracjanpolak@gmail.com
-- Stability   : alpha
-- Portability : portable, ffi
--
-- A Haskell wrapper library for a scripting language Lua.
-- See @http:\/\/www.lua.org\/@ for more details.
--
-- This module is intended to be imported @qualified@, eg.
--
-- > import qualified Scripting.Lua as Lua
--
-- This way we use Haskell module hierarchy to make Lua names shorter.
-- Haskell functions are named after Lua functions, but the @lua_@ or
-- @luaL_@ prefix.
--
-- Lua types are mapped to Haskell types as in the following table:
--
-- > int (stack index)        Int
-- > lua_Integer              LuaInteger
-- > lua_Number               LuaNumber
-- > int (bool result)        Bool
-- > const char * (string)    String
-- > void *                   Ptr ()
-- > lua_State *              LuaState
--
-- Most functions are one-to-one mappings.
-- Rare special cases are clearly marked in this document.
--
-- Minmal sample embedding:
--
-- > import qualified Scripting.Lua as Lua
--
-- > main = do
-- >     l <- Lua.newstate
-- >     Lua.openlibs l
-- >     Lua.callproc l "print" "Hello from Lua"
-- >     Lua.close l

module Scripting.LuaModded
(
    -- * Basic Lua types
    LuaState(..),

    -- * Constants and enumerations
    LTYPE(..),
    multret,

    -- * lua_* functions
    close,
    getglobal,
    gettop,
    isboolean,
    isnoneornil,
    isnumber,
    isstring,
    istable,
    newstate,
    newtable,
    next,
    pcall,
    pop,
    pushboolean,
    pushinteger,
    pushnil,
    pushnumber,
    pushstring,
    pushbytestring,
    rawget,
    remove,
    setglobal,
    settable,
    toboolean,
    tointeger,
    tonumber,
    tostring,
    tobytestring,
    ltype,

    -- * luaL_* functions
    openlibs,
    safeloadstring,

    -- * Haskell extensions
    StackValue(..),
    pushhsfunction_raw,
--    registerhsfunction
)
where
import Prelude hiding (error,concat)
import Foreign.C
import Foreign.Ptr
import Foreign.StablePtr
import Control.Monad
import Foreign.Marshal.Alloc
---import Data.IORef
import qualified Foreign.Storable as F
--import qualified Data.List as L
--import Data.Maybe
import qualified Data.ByteString
import qualified Data.ByteString.Char8
import qualified Control.Exception



-- | Wrapper for @lua_State *@. See @lua_State@ in Lua Reference Manual.
newtype LuaState = LuaState (Ptr ())
-- | Wrapper for @lua_Alloc@. See @lua_Alloc@ in Lua Reference Manual.
-- type LuaAlloc = Ptr () -> Ptr () -> CInt -> CInt -> IO (Ptr ())
-- | Wrapper for @lua_Reader@. See @lua_Reader@ in Lua Reference Manual.
---type LuaReader = Ptr () -> Ptr () -> Ptr CInt -> IO (Ptr CChar)

-- | Wrapper for @lua_Writer@. See @lua_Writer@ in Lua Reference Manual.
---type LuaWriter = LuaState -> Ptr CChar -> CInt -> Ptr () -> IO CInt
-- | Wrapper for @lua_CFunction@. See @lua_CFunction@ in Lua Reference Manual.
type LuaCFunction = LuaState -> IO CInt
-- | Wrapper for @lua_Integer@. See @lua_Integer@ in Lua Reference Manual.
-- HsLua uses C @ptrdiff_t@ as @lua_Integer@.
type LuaInteger = CPtrdiff
-- | Wrapper for @lua_Number@. See @lua_Number@ in Lua Reference Manual.
-- HsLua uses C @double@ as @lua_Integer@.
type LuaNumber = CDouble


-- | Enumeration used as type tag. See @lua_type@ in Lua Reference Manual.
data LTYPE = TNONE
           | TNIL
           | TBOOLEAN
           | TLIGHTUSERDATA
           | TNUMBER
           | TSTRING
           | TTABLE
           | TFUNCTION
           | TUSERDATA
           | TTHREAD
           | T_ENUMERROR
           deriving (Eq,Show,Ord)

instance Enum LTYPE where
    fromEnum TNONE           = -1
    fromEnum TNIL            = 0
    fromEnum TBOOLEAN        = 1
    fromEnum TLIGHTUSERDATA  = 2
    fromEnum TNUMBER         = 3
    fromEnum TSTRING         = 4
    fromEnum TTABLE          = 5
    fromEnum TFUNCTION       = 6
    fromEnum TUSERDATA       = 7
    fromEnum TTHREAD         = 8
    fromEnum T_ENUMERROR     = -2
    toEnum (-1) = TNONE
    toEnum 0 = TNIL
    toEnum 1 = TBOOLEAN
    toEnum 2 = TLIGHTUSERDATA
    toEnum 3 = TNUMBER
    toEnum 4 = TSTRING
    toEnum 5 = TTABLE
    toEnum 6 = TFUNCTION
    toEnum 7 = TUSERDATA
    toEnum 8 = TTHREAD
    toEnum _ = T_ENUMERROR

-- | Enumeration used by @gc@ function.
data GCCONTROL  = GCSTOP
                | GCRESTART
                | GCCOLLECT
                | GCCOUNT
                | GCCOUNTB
                | GCSTEP
                | GCSETPAUSE
                | GCSETSTEPMUL
                deriving (Eq,Ord,Show,Enum)

-- | See @LUA_MULTRET@ in Lua Reference Manual.
multret :: Int
multret = -1

{-

It is unknown which of the imported function may trigger garbage collector.
GC may in turn call some finalizars that will require come back to
the Haskell world.

This means we must declare almost all functions as 'safe'. This is slow, so
some functions known not to call gc are marked with faster 'unsafe' modifier.

-}
foreign import ccall "lua.h lua_close" c_lua_close :: LuaState -> IO ()
foreign import ccall "lua.h lua_newthread" c_lua_newthread :: LuaState -> IO LuaState
foreign import ccall "lua.h lua_atpanic" c_lua_atpanic :: LuaState -> FunPtr LuaCFunction -> IO (FunPtr LuaCFunction)


foreign import ccall "lua.h lua_gettop" c_lua_gettop :: LuaState -> IO CInt
foreign import ccall "lua.h lua_settop" c_lua_settop :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_pushvalue" c_lua_pushvalue :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_remove" c_lua_remove :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_insert" c_lua_insert :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_replace" c_lua_replace :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_checkstack" c_lua_checkstack :: LuaState -> CInt -> IO CInt
---foreign import ccall "lua.h lua_xmove" c_lua_xmove :: LuaState -> LuaState -> CInt -> IO ()


foreign import ccall "lua.h lua_isnumber" c_lua_isnumber :: LuaState -> CInt -> IO CInt
foreign import ccall "lua.h lua_isstring" c_lua_isstring :: LuaState -> CInt -> IO CInt
foreign import ccall "lua.h lua_iscfunction" c_lua_iscfunction :: LuaState -> CInt -> IO CInt
foreign import ccall "lua.h lua_isuserdata" c_lua_isuserdata :: LuaState -> CInt -> IO CInt
foreign import ccall "lua.h lua_type" c_lua_type :: LuaState -> CInt -> IO CInt
--foreign import ccall "lua.h lua_typename" c_lua_typename :: LuaState -> CInt -> IO (Ptr CChar)

foreign import ccall "lua.h lua_equal" c_lua_equal :: LuaState -> CInt -> CInt -> IO CInt
foreign import ccall "lua.h lua_rawequal" c_lua_rawequal :: LuaState -> CInt -> CInt -> IO CInt
foreign import ccall "lua.h lua_lessthan" c_lua_lessthan :: LuaState -> CInt -> CInt -> IO CInt

foreign import ccall "lua.h lua_tonumber" c_lua_tonumber :: LuaState -> CInt -> IO LuaNumber
foreign import ccall "lua.h lua_tointeger" c_lua_tointeger :: LuaState -> CInt -> IO LuaInteger
foreign import ccall "lua.h lua_toboolean" c_lua_toboolean :: LuaState -> CInt -> IO CInt
foreign import ccall "lua.h lua_tolstring" c_lua_tolstring :: LuaState -> CInt -> Ptr CInt -> IO (Ptr CChar)
foreign import ccall "lua.h lua_objlen" c_lua_objlen :: LuaState -> CInt -> IO CInt
foreign import ccall "lua.h lua_tocfunction" c_lua_tocfunction :: LuaState -> CInt -> IO (FunPtr LuaCFunction)
foreign import ccall "lua.h lua_touserdata" c_lua_touserdata :: LuaState -> CInt -> IO (Ptr a)
foreign import ccall "lua.h lua_tothread" c_lua_tothread :: LuaState -> CInt -> IO LuaState
foreign import ccall "lua.h lua_topointer" c_lua_topointer :: LuaState -> CInt -> IO (Ptr ())


foreign import ccall "lua.h lua_pushnil" c_lua_pushnil :: LuaState -> IO ()
foreign import ccall "lua.h lua_pushnumber" c_lua_pushnumber :: LuaState -> LuaNumber -> IO ()
foreign import ccall "lua.h lua_pushinteger" c_lua_pushinteger :: LuaState -> LuaInteger -> IO ()
foreign import ccall "lua.h lua_pushlstring" c_lua_pushlstring :: LuaState -> Ptr CChar -> CInt -> IO ()
foreign import ccall "lua.h lua_pushcclosure" c_lua_pushcclosure :: LuaState -> FunPtr LuaCFunction -> CInt -> IO ()
foreign import ccall "lua.h lua_pushboolean" c_lua_pushboolean :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_pushlightuserdata" c_lua_pushlightuserdata :: LuaState -> Ptr a -> IO ()
foreign import ccall "lua.h lua_pushthread" c_lua_pushthread :: LuaState -> IO CInt


foreign import ccall "lua.h lua_gettable" c_lua_gettable :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_getfield" c_lua_getfield :: LuaState -> CInt -> Ptr CChar -> IO ()
foreign import ccall "lua.h lua_rawget" c_lua_rawget :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_rawgeti" c_lua_rawgeti :: LuaState -> CInt -> CInt -> IO ()
foreign import ccall "lua.h lua_createtable" c_lua_createtable :: LuaState -> CInt -> CInt -> IO ()
foreign import ccall "lua.h lua_newuserdata" c_lua_newuserdata :: LuaState -> CInt -> IO (Ptr ())
foreign import ccall "lua.h lua_getmetatable" c_lua_getmetatable :: LuaState -> CInt -> IO CInt
foreign import ccall "lua.h lua_getfenv" c_lua_getfenv :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_getupvalue" c_lua_getupvalue :: LuaState -> CInt -> CInt -> IO (Ptr CChar)
foreign import ccall "lua.h lua_setupvalue" c_lua_setupvalue :: LuaState -> CInt -> CInt -> IO (Ptr CChar)


foreign import ccall "lua.h lua_settable" c_lua_settable :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_setfield" c_lua_setfield :: LuaState -> CInt -> Ptr CChar -> IO ()
foreign import ccall "lua.h lua_rawset" c_lua_rawset :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_rawseti" c_lua_rawseti :: LuaState -> CInt -> CInt -> IO ()
foreign import ccall "lua.h lua_setmetatable" c_lua_setmetatable :: LuaState -> CInt -> IO ()
foreign import ccall "lua.h lua_setfenv" c_lua_setfenv :: LuaState -> CInt -> IO CInt

foreign import ccall "lua.h lua_pcall" c_lua_pcall :: LuaState -> CInt -> CInt -> CInt -> IO CInt
foreign import ccall "lua.h lua_cpcall" c_lua_cpcall :: LuaState -> FunPtr LuaCFunction -> Ptr a -> IO CInt

---foreign import ccall "lua.h lua_load" c_lua_load :: LuaState -> FunPtr LuaReader -> Ptr () -> Ptr CChar -> IO CInt

---foreign import ccall "lua.h lua_dump" c_lua_dump :: LuaState -> FunPtr LuaWriter -> Ptr () -> IO ()

foreign import ccall "lua.h lua_yield" c_lua_yield :: LuaState -> CInt -> IO CInt
foreign import ccall "lua.h lua_resume" c_lua_resume :: LuaState -> CInt -> IO CInt
foreign import ccall "lua.h lua_status" c_lua_status :: LuaState -> IO CInt

foreign import ccall "lua.h lua_gc" c_lua_gc :: LuaState -> CInt -> CInt -> IO CInt

foreign import ccall "lua.h lua_next" c_lua_next :: LuaState -> CInt -> IO CInt

foreign import ccall "lua.h lua_concat" c_lua_concat :: LuaState -> CInt -> IO ()

foreign import ccall "lualib.h luaL_openlibs" c_luaL_openlibs :: LuaState -> IO ()
foreign import ccall "lauxlib.h luaL_newstate" c_luaL_newstate :: IO LuaState
foreign import ccall "lauxlib.h luaL_newmetatable" c_luaL_newmetatable :: LuaState -> Ptr CChar -> IO CInt
--foreign import ccall "lauxlib.h luaL_argerror" c_luaL_argerror :: LuaState -> CInt -> Ptr CChar -> IO CInt

foreign import ccall "lauxlib.h luaL_loadstring" c_luaL_loadstring :: LuaState -> Ptr CChar -> IO CInt

foreign import ccall "ntrljmp.h &lua_neutralize_longjmp" c_lua_neutralize_longjmp_addr :: FunPtr (LuaState -> IO CInt) 


-- | See @lua_settop@ in Lua Reference Manual.
settop :: LuaState -> Int -> IO ()
settop l n = c_lua_settop l (fromIntegral n)

-- | See @lua_createtable@ in Lua Reference Manual.
createtable :: LuaState -> Int -> Int -> IO ()
createtable l s z = c_lua_createtable l (fromIntegral s) (fromIntegral z)

-- | See @lua_objlen@ in Lua Reference Manual.
_objlen :: LuaState -> Int -> IO Int
_objlen l n = liftM fromIntegral (c_lua_objlen l (fromIntegral n))

-- | See @lua_pop@ in Lua Reference Manual.
pop :: LuaState -> Int -> IO ()
pop l n = settop l (-n-1)


-- | See @lua_newtable@ in Lua Reference Manual.
newtable :: LuaState -> IO ()
newtable l = createtable l 0 0

-- | See @lua_pushcclosure@ in Lua Reference Manual.
_pushcclosure :: LuaState -> FunPtr LuaCFunction -> Int -> IO ()
_pushcclosure l f n = c_lua_pushcclosure l f (fromIntegral n)

-- | See @lua_pushcfunction@ in Lua Reference Manual.
pushcfunction :: LuaState -> FunPtr LuaCFunction -> IO ()
pushcfunction l f = _pushcclosure l f 0


-- | See @lua_strlen@ in Lua Reference Manual.
-- strlen :: LuaState -> Int -> IO Int
-- strlen l i =  objlen l i

-- | See @lua_type@ in Lua Reference Manual.
ltype :: LuaState -> Int -> IO LTYPE
ltype l n = liftM (toEnum . fromIntegral) (c_lua_type l (fromIntegral n))

-- | See @lua_isfunction@ in Lua Reference Manual.
_isfunction :: LuaState -> Int -> IO Bool
_isfunction l n = liftM (==TFUNCTION) (ltype l n)

-- | See @lua_istable@ in Lua Reference Manual.
istable :: LuaState -> Int -> IO Bool
istable l n = liftM (==TTABLE) (ltype l n)

-- | See @lua_islightuserdata@ in Lua Reference Manual.
_islightuserdata :: LuaState -> Int -> IO Bool
_islightuserdata l n = liftM (==TLIGHTUSERDATA) (ltype l n)

-- | See @lua_isnil@ in Lua Reference Manual.
isnil :: LuaState -> Int -> IO Bool
isnil l n = liftM (==TNIL) (ltype l n)

-- | See @lua_isboolean@ in Lua Reference Manual.
isboolean :: LuaState -> Int -> IO Bool
isboolean l n = liftM (==TBOOLEAN) (ltype l n)

-- | See @lua_isthread@ in Lua Reference Manual.
_isthread :: LuaState -> Int -> IO Bool
_isthread l n = liftM (==TTHREAD) (ltype l n)

-- | See @lua_none@ in Lua Reference Manual.
_isnone :: LuaState -> Int -> IO Bool
_isnone l n = liftM (==TNONE) (ltype l n)

-- | See @lua_noneornil@ in Lua Reference Manual.
isnoneornil :: LuaState -> Int -> IO Bool
isnoneornil l n = liftM (<=TNIL) (ltype l n)

-- | See @LUA_REGISTRYINDEX@ in Lua Reference Manual.
_registryindex :: Int
_registryindex = (-10000)

-- | See @LUA_ENVIRONINDEX@ in Lua Reference Manual.
_environindex :: Int
_environindex = (-10001)

-- | See @LUA_GLOBALSINDEX@ in Lua Reference Manual.
globalsindex :: Int
globalsindex = (-10002)

-- | See @lua_upvalueindex@ in Lua Reference Manual.
_upvalueindex :: Int -> Int
_upvalueindex i = (globalsindex-(i))

{-
The following seem to be really bad idea, as calls from C
back to Haskell land are costly.

Use standard Lua malloc based allocator.

foreign export ccall "hslua_alloc" hslua_alloc :: Ptr () -> Ptr () -> CInt -> CInt -> IO (Ptr ())
foreign import ccall "&hslua_alloc" hslua_alloc_addr :: FunPtr LuaAlloc

hslua_alloc :: Ptr () -> Ptr () -> CInt -> CInt -> IO (Ptr ())
hslua_alloc ud ptr osize nsize = reallocBytes ptr (fromIntegral nsize)

static void *l_alloc (void *ud, void *ptr, size_t osize,
                                                size_t nsize) {
       (void)ud;  (void)osize;  /* not used */
       if (nsize == 0) {
         free(ptr);
         return NULL;
       }
       else
         return realloc(ptr, nsize);
     }
-}

-- | See @lua_atpanic@ in Lua Reference Manual.
_atpanic :: LuaState -> FunPtr LuaCFunction -> IO (FunPtr LuaCFunction)
_atpanic = c_lua_atpanic

-- | See @lua_tostring@ in Lua Reference Manual.
tostring :: LuaState -> Int -> IO String
tostring l n = do
	isstr <- isstring l n
	if isstr
		then c_lua_tolstring l (fromIntegral n) nullPtr >>= peekCString
		else Control.Exception.throwIO $ userError $ "bad argument #1 to 'tostring' (string expected)"

tobytestring :: LuaState -> Int -> IO Data.ByteString.ByteString
tobytestring l n = do
	isstr <- isstring l n
	if isstr
		then do
			lenptr <- Foreign.Marshal.Alloc.malloc :: IO (Ptr CInt)
			ptr <- c_lua_tolstring l (fromIntegral n) lenptr
			len <- F.peek lenptr
			Foreign.Marshal.Alloc.free lenptr
			Data.ByteString.packCStringLen (ptr, fromIntegral len)
		else Control.Exception.throwIO $ userError $ "bad argument #1 to 'tobytestring' (string expected)"

-- | See @lua_tothread@ in Lua Reference Manual.
_tothread :: LuaState -> Int -> IO LuaState
_tothread l n = c_lua_tothread l (fromIntegral n)

-- | See @lua_touserdata@ in Lua Reference Manual.
touserdata :: LuaState -> Int -> IO (Ptr a)
touserdata l n = c_lua_touserdata l (fromIntegral n)

-- | See @lua_typename@ in Lua Reference Manual.
--typename :: LuaState -> LTYPE -> IO String
--typename l n = c_lua_typename l (fromIntegral (fromEnum n)) >>= peekCString

-- | See @lua_xmove@ in Lua Reference Manual.
---xmove :: LuaState -> LuaState -> Int -> IO ()
---xmove l1 l2 n = c_lua_xmove l1 l2 (fromIntegral n)

-- | See @lua_yield@ in Lua Reference Manual.
_yield :: LuaState -> Int -> IO Int
_yield l n = liftM fromIntegral (c_lua_yield l (fromIntegral n))

-- | See @lua_checkstack@ in Lua Reference Manual.
_checkstack :: LuaState -> Int -> IO Bool
_checkstack l n = liftM (/=0) (c_lua_checkstack l (fromIntegral n))

-- | See @lua_newstate@ and @luaL_newstate@ in Lua Reference Manual.
newstate :: IO LuaState
newstate = c_luaL_newstate

-- | See @lua_close@ in Lua Reference Manual.
close :: LuaState -> IO ()
close = c_lua_close

-- | See @lua_concat@ in Lua Reference Manual.
_concat :: LuaState -> Int -> IO ()
_concat l n = c_lua_concat l (fromIntegral n)



-- | See @lua_call@ and @lua_call@ in Lua Reference Manual. This is 
-- a wrapper over @lua_pcall@, as @lua_call@ is unsafe in controlled environment
-- like Haskell VM.
_call :: LuaState -> Int -> Int -> IO Int
_call l a b = liftM fromIntegral (c_lua_pcall l (fromIntegral a) (fromIntegral b) 0)

-- | See @lua_pcall@ in Lua Reference Manual.
pcall :: LuaState -> Int -> Int -> Int -> IO Int
pcall l a b c = liftM fromIntegral (c_lua_pcall l (fromIntegral a) (fromIntegral b) (fromIntegral c))

-- | See @lua_cpcall@ in Lua Reference Manual.
_cpcall :: LuaState -> FunPtr LuaCFunction -> Ptr a -> IO Int
_cpcall l a c = liftM fromIntegral (c_lua_cpcall l a c)

-- | See @lua_getfield@ in Lua Reference Manual.
getfield :: LuaState -> Int -> String -> IO ()
getfield l i n = withCString n $ \n -> c_lua_getfield l (fromIntegral i) n

-- | See @lua_setfield@ in Lua Reference Manual.
setfield :: LuaState -> Int -> String -> IO ()
setfield l i n = withCString n $ \n -> c_lua_setfield l (fromIntegral i) n

-- | See @lua_getglobal@ in Lua Reference Manual.
getglobal :: LuaState -> String -> IO ()
getglobal l n = getfield l globalsindex n

-- | See @lua_setglobal@ in Lua Reference Manual.
setglobal :: LuaState -> String -> IO ()
setglobal l n = setfield l globalsindex n

-- | See @luaL_openlibs@ in Lua Reference Manual.
openlibs :: LuaState -> IO ()
openlibs = c_luaL_openlibs

---foreign import ccall "wrapper" mkStringWriter :: LuaWriter -> IO (FunPtr LuaWriter)

---dump :: LuaState -> IO String
---dump l = do
---    r <- newIORef ""
---    let wr :: LuaWriter
---        wr _l p s _d = do
---               k <- peekCStringLen (p,fromIntegral s)
---               modifyIORef r (++k)
---               return 0
---    writer <- mkStringWriter wr
---    c_lua_dump l writer nullPtr
---    freeHaskellFunPtr writer
---    readIORef r

-- | See @lua_equal@ in Lua Reference Manual.
_equal :: LuaState -> Int -> Int -> IO Bool
_equal l i j = liftM (/=0) (c_lua_equal l (fromIntegral i) (fromIntegral j))

-- | See @lua_error@ in Lua Reference Manual.
--error :: LuaState -> IO Int
--error l = liftM fromIntegral (c_lua_error l)

-- | See @lua_gc@ in Lua Reference Manual.
_gc :: LuaState -> GCCONTROL -> Int -> IO Int
_gc l i j= liftM fromIntegral (c_lua_gc l (fromIntegral (fromEnum i)) (fromIntegral j))

-- | See @lua_getfenv@ in Lua Reference Manual.
_getfenv :: LuaState -> Int -> IO ()
_getfenv l n = c_lua_getfenv l (fromIntegral n)

-- | See @lua_getmetatable@ in Lua Reference Manual.
_getmetatable :: LuaState -> Int -> IO Bool
_getmetatable l n = liftM (/=0) (c_lua_getmetatable l (fromIntegral n))

-- | See @lua_gettable@ in Lua Reference Manual.
_gettable :: LuaState -> Int -> IO ()
_gettable l n = c_lua_gettable l (fromIntegral n)

-- | See @lua_gettop@ in Lua Reference Manual.
gettop :: LuaState -> IO Int
gettop l = liftM fromIntegral (c_lua_gettop l)

-- | See @lua_getupvalue@ in Lua Reference Manual.
_getupvalue :: LuaState -> Int -> Int -> IO String
_getupvalue l funcindex n = c_lua_getupvalue l (fromIntegral funcindex) (fromIntegral n) >>= peekCString

-- | See @lua_insert@ in Lua Reference Manual.
_insert :: LuaState -> Int -> IO ()
_insert l n  = c_lua_insert l (fromIntegral n)

-- | See @lua_iscfunction@ in Lua Reference Manual.
iscfunction :: LuaState -> Int -> IO Bool
iscfunction l n = liftM (/=0) (c_lua_iscfunction l (fromIntegral n))

-- | See @lua_isnumber@ in Lua Reference Manual.
isnumber :: LuaState -> Int -> IO Bool
isnumber l n = liftM (/=0) (c_lua_isnumber l (fromIntegral n))

-- | See @lua_isstring@ in Lua Reference Manual.
isstring :: LuaState -> Int -> IO Bool
isstring l n = liftM (/=0) (c_lua_isstring l (fromIntegral n))

-- | See @lua_isuserdata@ in Lua Reference Manual.
isuserdata :: LuaState -> Int -> IO Bool
isuserdata l n = liftM (/=0) (c_lua_isuserdata l (fromIntegral n))

-- | See @lua_lessthan@ in Lua Reference Manual.
_lessthan :: LuaState -> Int -> Int -> IO Bool
_lessthan l i j = liftM (/=0) (c_lua_lessthan l (fromIntegral i) (fromIntegral j))


-- | See @luaL_loadfile@ in Lua Reference Manual.
---loadfile :: LuaState -> String -> IO Int
---loadfile l f = readFile f >>= \c -> loadstring l c f


---foreign import ccall "wrapper" mkStringReader :: LuaReader -> IO (FunPtr LuaReader)

-- | See @luaL_loadstring@ in Lua Reference Manual.
---loadstring :: LuaState -> String -> String -> IO Int
---loadstring l script cn = do
---    w <- newIORef nullPtr
---    let rd :: LuaReader
---        rd _l _d ps = do
---               k <- readIORef w
---               if k==nullPtr
---                   then do
---                       (k,l) <- newCStringLen script
---                       writeIORef w k
---                       F.poke ps (fromIntegral l)
---                       return k
---                   else do
---                       return nullPtr
---    writer <- mkStringReader rd
---    res <- withCString cn $ \cn -> c_lua_load l writer nullPtr cn
---    freeHaskellFunPtr writer
---    k <- readIORef w
---    free k
---    return (fromIntegral res)

-- | See @lua_newthread@ in Lua Reference Manual.
_newthread :: LuaState -> IO LuaState
_newthread l = c_lua_newthread l

-- | See @lua_newuserdata@ in Lua Reference Manual.
newuserdata :: LuaState -> Int -> IO (Ptr ())
newuserdata l s = c_lua_newuserdata l (fromIntegral s)

-- | See @lua_next@ in Lua Reference Manual.
next :: LuaState -> Int -> IO Bool
next l i = liftM (/=0) (c_lua_next l (fromIntegral i))

-- | See @lua_pushboolean@ in Lua Reference Manual.
pushboolean :: LuaState -> Bool -> IO ()
pushboolean l v = c_lua_pushboolean l (fromIntegral (fromEnum v))

-- | See @lua_pushinteger@ in Lua Reference Manual.
pushinteger :: LuaState -> Integer -> IO ()
pushinteger l i = c_lua_pushinteger l (fromIntegral i)

-- | See @lua_pushlightuserdata@ in Lua Reference Manual.
pushlightuserdata :: LuaState -> Ptr a -> IO ()
pushlightuserdata = c_lua_pushlightuserdata

-- | See @lua_pushnil@ in Lua Reference Manual.
pushnil :: LuaState -> IO ()
pushnil = c_lua_pushnil

-- | See @lua_pushnumber@ in Lua Reference Manual.
pushnumber :: LuaState -> LuaNumber -> IO ()
pushnumber = c_lua_pushnumber

-- | See @lua_pushstring@ in Lua Reference Manual.
pushstring :: LuaState -> String -> IO ()
pushstring l s = withCStringLen s $ \(s,z) -> c_lua_pushlstring l s (fromIntegral z)

pushbytestring :: LuaState -> Data.ByteString.ByteString -> IO ()
pushbytestring l s = Data.ByteString.useAsCStringLen s $ \(s,z) -> c_lua_pushlstring l s (fromIntegral z)

-- | See @lua_pushthread@ in Lua Reference Manual.
_pushthread :: LuaState -> IO Bool
_pushthread l = liftM (/=0) (c_lua_pushthread l)

-- | See @lua_pushvalue@ in Lua Reference Manual.
_pushvalue :: LuaState -> Int -> IO ()
_pushvalue l n = c_lua_pushvalue l (fromIntegral n)

-- | See @lua_rawequal@ in Lua Reference Manual.
_rawequal :: LuaState -> Int -> Int -> IO Bool
_rawequal l n m = liftM (/=0) (c_lua_rawequal l (fromIntegral n) (fromIntegral m))

-- | See @lua_rawget@ in Lua Reference Manual.
rawget :: LuaState -> Int -> IO ()
rawget l n = c_lua_rawget l (fromIntegral n)

-- | See @lua_rawgeti@ in Lua Reference Manual.
_rawgeti :: LuaState -> Int -> Int -> IO ()
_rawgeti l k m = c_lua_rawgeti l (fromIntegral k) (fromIntegral m)

-- | See @lua_rawset@ in Lua Reference Manual.
_rawset :: LuaState -> Int -> IO ()
_rawset l n = c_lua_rawset l (fromIntegral n)

-- | See @lua_rawseti@ in Lua Reference Manual.
_rawseti :: LuaState -> Int -> Int -> IO ()
_rawseti l k m = c_lua_rawseti l (fromIntegral k) (fromIntegral m)

-- | See @lua_remove@ in Lua Reference Manual.
remove :: LuaState -> Int -> IO ()
remove l n = c_lua_remove l (fromIntegral n)

-- | See @lua_replace@ in Lua Reference Manual.
_replace :: LuaState -> Int -> IO ()
_replace l n = c_lua_replace l (fromIntegral n)

-- | See @lua_resume@ in Lua Reference Manual.
_resume :: LuaState -> Int -> IO Int
_resume l n = liftM fromIntegral (c_lua_resume l (fromIntegral n))

-- | See @lua_setfenv@ in Lua Reference Manual.
_setfenv :: LuaState -> Int -> IO Int
_setfenv l n = liftM fromIntegral (c_lua_setfenv l (fromIntegral n))

-- | See @lua_setmetatable@ in Lua Reference Manual.
setmetatable :: LuaState -> Int -> IO ()
setmetatable l n = c_lua_setmetatable l (fromIntegral n)

-- | See @lua_settable@ in Lua Reference Manual.
settable :: LuaState -> Int -> IO ()
settable l index = c_lua_settable l (fromIntegral index)


-- | See @lua_setupvalue@ in Lua Reference Manual.
_setupvalue :: LuaState -> Int -> Int -> IO String
_setupvalue l funcindex n = c_lua_setupvalue l (fromIntegral funcindex) (fromIntegral n) >>= peekCString

-- | See @lua_status@ in Lua Reference Manual.
_status :: LuaState -> IO Int
_status l = liftM fromIntegral (c_lua_status l)

-- | See @lua_toboolean@ in Lua Reference Manual.
toboolean :: LuaState -> Int -> IO Bool
toboolean l n = liftM (/=0) (c_lua_toboolean l (fromIntegral n))

-- | See @lua_tocfunction@ in Lua Reference Manual.
tocfunction :: LuaState -> Int -> IO (FunPtr LuaCFunction)
tocfunction l n = c_lua_tocfunction l (fromIntegral n)

-- | See @lua_tointeger@ in Lua Reference Manual.
tointeger :: LuaState -> Int -> IO Integer
tointeger l n = do
	intval <- c_lua_tointeger l (fromIntegral n)
	return (fromIntegral intval)

-- | See @lua_tonumber@ in Lua Reference Manual.
tonumber :: LuaState -> Int -> IO CDouble
tonumber l n = c_lua_tonumber l (fromIntegral n)

-- | See @lua_topointer@ in Lua Reference Manual.
_topointer :: LuaState -> Int -> IO (Ptr ())
_topointer l n = c_lua_topointer l (fromIntegral n)

-- | See @lua_register@ in Lua Reference Manual.
_register :: LuaState -> String -> FunPtr LuaCFunction -> IO ()
_register l n f = do
    _pushcclosure l f 0
    setglobal l n

-- | See @luaL_newmetatable@ in Lua Reference Manual.
newmetatable :: LuaState -> String -> IO Int
newmetatable l s = withCString s $ \s -> liftM fromIntegral (c_luaL_newmetatable l s)

safeloadstring :: LuaState -> String -> IO Int
safeloadstring l s = withCString s $ \s -> liftM fromIntegral (c_luaL_loadstring l s)

-- | See @luaL_argerror@ in Lua Reference Manual. Contrary to the 
-- manual, Haskell function does return with value less than zero.
--argerror :: LuaState -> Int -> String -> IO CInt
--argerror l n msg = withCString msg $ \msg -> do
--    let doit l = c_luaL_argerror l (fromIntegral n) msg
--    f <- mkWrapper doit
--    c_lua_cpcall l f nullPtr
--    freeHaskellFunPtr f
--    -- here we should have error message string on top of the stack
--    return (-1)



-- | A value that can be pushed and poped from the Lua stack.
-- All instances are natural, except following:
--
--  * @LuaState@ push ignores its argument, pushes current state
--
--  * @()@ push ignores its argument, just pushes nil
--
--  * @Ptr ()@ pushes light user data, peek checks for lightuserdata or userdata
class StackValue a where
    -- | Pushes a value onto Lua stack, casting it into meaningfully nearest Lua type.
    push :: LuaState -> a -> IO ()
    -- | Check if at index @n@ there is a convertible Lua value and if so return it
    -- wrapped in @Just@. Return @Nothing@ otherwise.
    peek :: LuaState -> Int -> IO (Maybe a)
    -- | Lua type id code of the vaule expected. Parameter is unused.
    valuetype :: a -> LTYPE

maybepeek l n test peek = do
    v <- test l n
    if v
        then liftM Just (peek l n)
        else return Nothing

--instance StackValue LuaInteger where
--    push l x = pushinteger l x
--    peek l n = maybepeek l n isnumber tointeger
--    valuetype _ = TNUMBER

--instance StackValue LuaNumber where
--    push l x = pushnumber l x
--    peek l n = maybepeek l n isnumber tonumber
--    valuetype _ = TNUMBER

--instance StackValue Int where
--    push l x = pushinteger l (fromIntegral x)
--    peek l n = maybepeek l n isnumber (\l n -> liftM fromIntegral (tointeger l n))
--    valuetype _ = TNUMBER

instance StackValue Double where
    push l x = pushnumber l (realToFrac x)
    peek l n = maybepeek l n isnumber (\l n -> liftM realToFrac (tonumber l n))
    valuetype _ = TNUMBER

instance StackValue String where
    push l x = pushstring l x
    peek l n = maybepeek l n isstring (\l n -> do
		bytestr <- tobytestring l n
		return $ Data.ByteString.Char8.unpack bytestr)
    valuetype _ = TSTRING

instance StackValue Bool where
    push l x = pushboolean l x
    peek l n = maybepeek l n isboolean toboolean
    valuetype _ = TBOOLEAN

instance StackValue (FunPtr LuaCFunction) where
    push l x = pushcfunction l x
    peek l n = maybepeek l n iscfunction tocfunction
    valuetype _ = TFUNCTION

-- watch out for the asymetry here
instance StackValue (Ptr a) where
    push l x = pushlightuserdata l x
    peek l n = maybepeek l n isuserdata touserdata
    valuetype _ = TUSERDATA

-- watch out for push here
---instance StackValue LuaState where
    ---push l _ = pushthread l >> return ()
    ---peek l n = maybepeek l n isthread tothread
    ---valuetype _ = TTHREAD

instance StackValue () where
    push l _ = pushnil l
    peek l n = maybepeek l n isnil (\_l _n -> return ())
    valuetype _ = TNIL


{-
-- | Argument wrapper, to be used in connection with @callproc@ and @callfunc@.
arg :: StackValue a => a -> LuaState -> IO ()
arg a l = push l a

-- | Call a Lua procedure. Use as:
-- > callproc l "proc" [arg "abc", arg 1, arg 5]
callproc :: LuaState -> String -> [LuaState -> IO ()] -> IO ()
callproc l f as = do
    getglobal2 l f
    mapM_ ($ l) as
    call l (length as) 0

-- | Call a Lua function. Use as:
-- > v <- callfunc l "proc" [arg "abc", arg 1, arg 5]
callfunc :: StackValue a => LuaState -> String -> [LuaState -> IO ()] -> IO (Maybe a)
callfunc l f as = do
    getglobal2 l f
    mapM_ ($ l) as
    call l (length as) 1
    z <- peek l (-1)
    pop l 1
    return z
-}

-- | Like @getglobal@, but knows about packages. e. g.
--
-- > getglobal l "math.sin"
--
-- returns correct result
--getglobal2 :: LuaState -> String -> IO ()
--getglobal2 l n = do
--    getglobal l x
--    mapM_ dotable xs
--    where (x:xs) = splitdot n
--          splitdot = filter (/=".") . L.groupBy (\a b -> a/='.' && b/='.')
--          dotable x = getfield l (-1) x >> gettop l >>= \n -> remove l (n-1)
-- typenameindex l n = ltype l n >>= typename l

--class LuaImport a where
--    luaimport' :: Int -> a -> LuaCFunction
--    luaimportargerror :: Int -> String -> a -> LuaCFunction

--instance (StackValue a) => LuaImport (IO a) where
--    luaimportargerror n msg _x l = argerror l n msg
--    luaimport' _narg x l = x >>= push l >> return 1

--instance (StackValue a,LuaImport b) => LuaImport (a -> b) where
--    luaimportargerror n msg x l = luaimportargerror n msg (x undefined) l
--    {-
--     - FIXME: Cannot catch this exception here, because we are called from C,
--     - and error propagation, stack unwinding, etc does not work.
--     - Cannot call lua_error, because it uses longjmp and would skip two layers of abstraction.
--     -}
--    luaimport' narg x l = do
--        arg <- peek l narg
--        case arg of
--            Just v -> luaimport' (narg+1) (x v) l
--            Nothing -> do
--                t <- ltype l narg
--                exp <- typename l (valuetype (fromJust arg))
--                got <- typename l t
--                luaimportargerror narg (exp ++ " expected, got " ++ got) (x undefined) l

--foreign import ccall "wrapper" mkWrapper :: LuaCFunction -> IO (FunPtr LuaCFunction)

-- | Create new foreign Lua function. Function created can be called
-- by Lua engine. Remeber to free the pointer with @freecfunction@.
--newcfunction :: LuaImport a => a -> IO (FunPtr LuaCFunction)
--newcfunction = mkWrapper . luaimport

-- | Convert a Haskell function to Lua function. Any Haskell function
-- can be converted provided that:
--
--   * all arguments are instances of StackValue
--   * return type is IO t, where t is an instance of StackValue
--
-- Any Haskell exception will be converted to a string and returned
-- as Lua error.
--luaimport :: LuaImport a => a -> LuaCFunction
--luaimport a l = luaimport' 1 a l `Control.Exception.catch` (\e -> do
--    push l (show (e :: Control.Exception.SomeException))
--    return (-1))

-- | Free function pointer created with @newcfunction@.
--freecfunction :: FunPtr LuaCFunction -> IO ()
--freecfunction = freeHaskellFunPtr

--class LuaCallProc a where
--    callproc' :: LuaState -> String -> IO () -> Int -> a

-- | Call a Lua procedure. Use as:
--
-- > callproc l "proc" "abc" (1::Int) (5.0::Double)
--
--callproc :: (LuaCallProc a) => LuaState -> String -> a
--callproc l f = callproc' l f (return ()) 0

--class LuaCallFunc a where
--    callfunc' :: LuaState -> String -> IO () -> Int -> a

-- | Call a Lua function. Use as:
--
-- > Just v <- callfunc l "proc" "abc" (1::Int) (5.0::Double)
--callfunc :: (LuaCallFunc a) => LuaState -> String -> a
--callfunc l f = callfunc' l f (return ()) 0

--instance LuaCallProc (IO t) where
--    callproc' l f a k = do
--        getglobal2 l f
--        a
--        z <- pcall l k 0 0
--        if z/=0
--            then do
--                Just msg <- peek l (-1)
--                pop l 1
--                Prelude.fail msg
--            else do
--                return undefined

--instance (StackValue t) => LuaCallFunc (IO t) where
--    callfunc' l f a k = do
--        getglobal2 l f
--        a
--        z <- pcall l k 1 0
--        if z/=0
--            then do
--                Just msg <- peek l (-1)
--                pop l 1
--                Prelude.fail msg
--            else do
--                r <- peek l (-1)
--                pop l 1
--                case r of
--                    Just x -> return x
--                    Nothing -> do
--                        exp <- typename l (valuetype (fromJust r))
--                        t <- ltype l (-1)
--                        got <- typename l t
--                        Prelude.fail ("Incorrect result type (" ++ exp ++ " expected, got " ++ got ++ ")")

--instance (StackValue t,LuaCallProc b) => LuaCallProc (t -> b) where
--    callproc' l f a k x = callproc' l f (a >> push l x) (k+1)

--instance (StackValue t,LuaCallFunc b) => LuaCallFunc (t -> b) where
--    callfunc' l f a k x = callfunc' l f (a >> push l x) (k+1)


foreign export ccall hsmethod__gc :: LuaState -> IO CInt
foreign import ccall "&hsmethod__gc" hsmethod__gc_addr :: FunPtr LuaCFunction

foreign export ccall hsmethod__call :: LuaState -> IO CInt
-- foreign import ccall "&hsmethod__call" hsmethod__call_addr :: FunPtr LuaCFunction

hsmethod__gc :: LuaState -> IO CInt
hsmethod__gc l = do
	Just ptr <- peek l (-1)
	stableptr <- F.peek (castPtr ptr)
	freeStablePtr stableptr
	return 0

hsmethod__call :: LuaState -> IO CInt
hsmethod__call l = do
	Just ptr <- peek l (1)
	remove l 1
	stableptr <- F.peek (castPtr ptr)
	f <- deRefStablePtr stableptr
	f l

pushhsfunction_raw :: LuaState -> LuaCFunction -> IO ()
pushhsfunction_raw l f = do
    stableptr <- newStablePtr f
    p <- newuserdata l (F.sizeOf stableptr)
    F.poke (castPtr p) stableptr
    v <- newmetatable l "HaskellImportedFunction"
    when (v /= 0) $ do
        -- create new metatable, fill it with two entries __gc and __call
        push l hsmethod__gc_addr
        setfield l (-2) "__gc"
        push l c_lua_neutralize_longjmp_addr
        setfield l (-2) "__call"
    setmetatable l (-2)
    return ()

-- | Pushes Haskell function converted to a Lua function.
-- All values created will be garbage collected. Use as:
--
-- > Lua.pushhsfunction l myfun
-- > Lua.setglobal l "myfun"
--
-- You are not allowed to use @lua_error@ anywhere, but
-- use an error code of (-1) to the same effect. Push
-- error message as the sole return value.
--pushhsfunction :: LuaImport a => LuaState -> a -> IO ()
--pushhsfunction l f = do
--    pushhsfunction_raw l (luaimport f)

-- | Imports a Haskell function and registers it at global name.
--registerhsfunction :: LuaImport a => LuaState -> String -> a -> IO ()
--registerhsfunction l n f = pushhsfunction l f >> setglobal l n
