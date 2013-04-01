
import 'dart:io';
import 'dart:math';
import 'dart:crypto';
import 'dart:json' as JSON;
import 'dart:async';
import 'dart:uri';

import 'package:http/http.dart' as http;
import "package:html5lib/dom.dart";
import "package:html5lib/dom_parsing.dart";
import "package:fukiya/fukiya.dart";
import "package:google_plus_v1_api/plus_v1_api_console.dart" as plus;
import "package:google_oauth2_client/google_oauth2_console.dart" as console_auth;
import "package:logging/logging.dart";

final String CLIENT_ID = "327285194570-kbpkgvfe87tlvpue69lf5krdokbepo6j.apps.googleusercontent.com";
final String CLIENT_SECRET = "G6KLdY07klgrDKT2jcAYVE45";

final String TOKENINFO_URL = "https://www.googleapis.com/oauth2/v1/tokeninfo";
final String TOKEN_ENDPOINT = 'https://accounts.google.com/o/oauth2/token';
final String TOKEN_REVOKE_ENDPOINT = 'https://accounts.google.com/o/oauth2/revoke';

final Random random = new Random();
final Logger serverLogger = new Logger("server");

_setupLogger() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord logRecord) {
    StringBuffer sb = new StringBuffer();
    sb
    ..write(logRecord.time.toString())..write(":")
    ..write(logRecord.loggerName)..write(":")
    ..write(logRecord.level.name)..write(":")
    ..write(logRecord.sequenceNumber)..write(": ")
    ..write(logRecord.message.toString());
    print(sb.toString());
  });
}

class SimpleOAuth2 implements console_auth.OAuth2Console {
  final Logger logger = new Logger("SimpleOAuth2");
  
  console_auth.Credentials _credentials;
  console_auth.Credentials get credentials => _credentials;
  void set credentials(value) {
    _credentials = value;
  }
  console_auth.SystemCache _systemCache;
  console_auth.SystemCache get systemCache => _systemCache;
  
  void clearCredentials(console_auth.SystemCache cache) {
    logger.fine("clearCredentials(console_auth.SystemCache $cache)");
  }
  
  Future withClient(Future fn(console_auth.Client client)) {
    logger.fine("withClient(Future ${fn}(console_auth.Client client))");
    console_auth.Client _httpClient = new console_auth.Client(CLIENT_ID, CLIENT_SECRET, _credentials);
    return fn(_httpClient);
  }
  
  void close() {
    logger.fine("close()");
  } 
}

void main() {
  _setupLogger();
  
  new Fukiya()
  ..get('/', getIndexHandler)
  ..get('/index.html', getIndexHandler)
  ..get('/index', getIndexHandler)
  ..post('/connect', postConnectDataHandler)
  ..get('/people', getPeopleHandler)
  ..post('/disconnect', postDisconnectHandler)
  ..staticFiles('./web')
  ..use(new FukiyaJsonParser())
  ..listen('127.0.0.1', 3333);
}

void postDisconnectHandler(FukiyaContext context) {
  serverLogger.fine("postDisconnectHandler");
  
  String tokenData = context.request.session.containsKey("token") ? context.request.session["token"] : null;
  if (tokenData == null) {
    context.response.statusCode = 401;
    context.send("Current user not connected.");
    return;
  }
  
  final String revokeTokenUrl = "${TOKEN_REVOKE_ENDPOINT}?token=${tokenData}";
  context.request.session.remove("token");
  
  new http.Client()..get(revokeTokenUrl).then((http.Response response) {
    serverLogger.fine("GET ${revokeTokenUrl}");
    serverLogger.fine("Response = ${response.body}");
    context.send("Successfully disconnected.");
  });
}

void getPeopleHandler(FukiyaContext context) {
  serverLogger.fine("getPeopleHandler");
  String accessToken = context.request.session.containsKey("access_token") ? context.request.session["access_token"] : null;
  SimpleOAuth2 simpleOAuth2 = new SimpleOAuth2();
  console_auth.Credentials credentials = new console_auth.Credentials(accessToken);
  simpleOAuth2.credentials = credentials;
  plus.Plus plusclient = new plus.Plus(simpleOAuth2);
  plusclient.makeAuthRequests = true;
  plusclient.people.list("me", "visible").then((plus.PeopleFeed people) {
    serverLogger.fine("/people = $people");
    context.send(people.toString());
  });
}

void postConnectDataHandler(FukiyaContext context) {
  serverLogger.fine("postConnectDataHandler");
  String tokenData = context.request.session.containsKey("token") ? context.request.session["token"] : null; // TODO: handle missing token
  String stateToken = context.request.session.containsKey("state_token") ? context.request.session["state_token"] : null;
  String queryStateToken = context.request.queryParameters.containsKey("state_token") ? context.request.queryParameters["state_token"] : null;
  
  // Check if the token already exists for this session. 
  if (tokenData != null) {
    context.response.statusCode = 400;
    context.send("Current user is already connected.");
    return;
  }
  
  // Check if any of the needed token values are null or mismatched.
  if (stateToken == null || queryStateToken == null || stateToken != queryStateToken) {
    context.send("POST FAILED tokenData == null || stateToken == null || queryStateToken == null || $stateToken != $queryStateToken"); 
    return;
  }
  
  // Normally the state would be a one-time use token, however in our
  // simple case, we want a user to be able to connect and disconnect
  // without reloading the page.  Thus, for demonstration, we don't
  // implement this best practice.
  context.request.session.remove("state_token");
  
  String gPlusId = context.request.queryParameters["gplus_id"];
  StringBuffer sb = new StringBuffer();
  // Read data from request.
  context.request
  .transform(new StringDecoder())
  .listen((data) => sb.write(data), onDone: () {
    //print(sb.toString());
    Map requestData = JSON.parse(sb.toString());
    
    Map fields = {
              "grant_type": "authorization_code",
              "code": requestData["code"],
              // http://www.riskcompletefailure.com/2013/03/postmessage-oauth-20.html
              "redirect_uri": "postmessage",
              "client_id": CLIENT_ID,
              "client_secret": CLIENT_SECRET
    };
    
    //print("trying to post auth code from console");
    
    //print("fields = $fields");
    http.Client _httpClient = new http.Client();
    _httpClient.post(TOKEN_ENDPOINT, fields: fields).then((http.Response response) {
      // At this point we have the token and refresh token.
      var credentials = JSON.parse(response.body);
      print("credentials = ${response.body}");
      _httpClient.close();
      
      var verifyTokenUrl = '${TOKENINFO_URL}?access_token=${credentials["access_token"]}';
      new http.Client()
      ..get(verifyTokenUrl).then((http.Response response)  {
        print("response = ${response.body}");
        
        var verifyResponse = JSON.parse(response.body);
        String userId = verifyResponse.containsKey("user_id") ? verifyResponse["user_id"] : null;
        String accessToken = credentials.containsKey("access_token") ? credentials["access_token"] : null;
        if (userId != null && userId == gPlusId && accessToken != null) {
          context.request.session["access_token"] = accessToken;
          context.send("POST OK");
        } else {
          context.send("POST FAILED ${userId} != ${gPlusId}"); 
        }
      });
    });
  });
}

/**
 * Sends the client a index file with state token to start the client
 * side authentication process.
 */
void getIndexHandler(FukiyaContext context) {
  serverLogger.fine("getIndexHandler");
  // Create a state token. 
  StringBuffer stateTokenBuffer = new StringBuffer();
  new MD5()
  ..add(random.nextDouble().toString().codeUnits)
  ..close().forEach((int s) => stateTokenBuffer.write(s.toRadixString(16)));
  String stateToken = stateTokenBuffer.toString();
  context.request.session["state_token"] = stateToken;
  
  // Readin the index file and add state token into the meta element. 
  var file = new File("./web/index.html");
  file.exists().then((bool exists) {
    if (exists) {
      file.readAsString().then((String indexDocument) {
        Document doc = new Document.html(indexDocument);
        Element metaState = new Element.html('<meta name="state_token" content="${stateToken}">');
        doc.head.children.add(metaState);
        context.response.writeBytes(doc.outerHtml.codeUnits);
        context.response.done.catchError((e) => print("File Response error: ${e}"));
        context.response.close();
      }, onError: (error) => print("error = $error"));
    } else {
      context.response.statusCode = 404;
      context.response.close();
    }
  });
}