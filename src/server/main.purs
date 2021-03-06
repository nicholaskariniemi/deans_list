module DeanList.Server.Main where 

import DeanList.Book (Book(Book), parseBooks)

import Control.Monad.Eff (Eff(..))
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Exception (Error(..), message)
import Debug.Trace (Trace(..), trace, print)
import Data.Function (Fn3(..), runFn3)
import Data.Foreign.EasyFFI (unsafeForeignFunction)
import Data.JSON (encode)
import Data.Maybe (Maybe(..), fromMaybe)
import Node.Encoding (Encoding(UTF8))
import Node.Express.App (App(..), listenHttp, use, useExternal, useOnError, get)
import Node.Express.Handler (Handler(..), setStatus, send, sendJson, getOriginalUrl, next, capture)
import Node.Express.Types (Request(..), Response(..), ExpressM(..))
import Node.FS.Sync (readTextFile)

foreign import staticMiddleware "var staticMiddleware = require('express').static"
    :: String -> Fn3 Request Response (ExpressM Unit) (ExpressM Unit)

logger :: Handler
logger = do
    url <- getOriginalUrl
    liftEff $ trace url
    next
    
getBooks :: String -> Handler
getBooks booksPath = do
  callback <- capture parseAndSendBooks 
  liftEff $ unsafeHttpGet booksPath callback

parseAndSendBooks s = do
  let books = fromMaybe [] $ parseBooks s
  send $ encode books

errorHandler :: Error -> Handler
errorHandler err = do
    setStatus 400
    sendJson {error: message err}
            
appSetup :: ServerConfig -> App
appSetup { booksPath = booksPath } = do
    use logger
    useExternal $ staticMiddleware "public"
    useOnError errorHandler
    get "/books" $ getBooks booksPath

foreign import unsafeHttpGet
"""
function unsafeHttpGet(url) {
  return function(onResponse){
  return function() {
    var request = require('request');
    request(url, function(error, response, body){
      console.log('Got body');
      console.log(body);
      onResponse(body)();
    });
  }
  }
}""" :: forall eff. String -> (String -> Eff ( | eff) Unit) -> Eff ( | eff) Unit

foreign import envVarImpl
"""
function envVarImpl(just, nothing, name) {
  var v = process.env[name];
  if(v !== undefined){
    return just(v);
  } else {
    return nothing;
  }
}""" :: forall a. Fn3 (a -> Maybe a) (Maybe a) String (Maybe a)

envVar :: forall a. String -> Maybe a
envVar s = runFn3 envVarImpl Just Nothing s

envVarOrDefault :: forall a. a -> String -> a
envVarOrDefault default' name = fromMaybe default' $ envVar name

type ServerConfig = {booksPath :: String, port :: Number}

loadServerConfig :: ServerConfig
loadServerConfig = {
  booksPath: envVarOrDefault "public/books" "DEANS_LIST_BOOKS_PATH",
  port: envVarOrDefault 8080 "DEANS_LIST_BOOKS_PORT"
  }

traceServerConfig :: forall a. ServerConfig -> a -> Eff (trace :: Trace) Unit
traceServerConfig {booksPath = booksPath, port = port} = \_ -> trace 
  ("Server running on port " ++ (show port) ++
  ", serving books from '" ++ booksPath ++ "'")

main =
  listenHttp (appSetup config) config.port $ traceServerConfig config
  where
    config = loadServerConfig
