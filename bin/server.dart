/*
Client ID: 327285194570-kbpkgvfe87tlvpue69lf5krdokbepo6j.apps.googleusercontent.com
Client secret: G6KLdY07klgrDKT2jcAYVE45
 */

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

Random random = new Random();

class SimpleOAuth2 implements console_auth.OAuth2Console {
  console_auth.Credentials _credentials;
  console_auth.Credentials get credentials => _credentials;
  void set credentials(value) {
    _credentials = value;
  }
  console_auth.SystemCache _systemCache;
  console_auth.SystemCache get systemCache => _systemCache;
  
  void clearCredentials(console_auth.SystemCache cache) {
    print("clearCredentials");
  }
  
  Future withClient(Future fn(console_auth.Client client)) {
    //var completer = new Completer();
    console_auth.Client _httpClient = new console_auth.Client("327285194570-kbpkgvfe87tlvpue69lf5krdokbepo6j.apps.googleusercontent.com",
        "G6KLdY07klgrDKT2jcAYVE45",
        _credentials);
    print("withClient");
    return fn(_httpClient);
  }
  
  void close() {
    print("close()");
  }
  
}

void main() {
  new Fukiya()
  ..get('/', getIndexHandler)
  ..get('/index.html', getIndexHandler)
  ..get('/index', getIndexHandler)
  ..post('/connect', postConnectDataHandler)
  ..get('/people', getPeopleHandler)
  ..staticFiles('./web')
  ..use(new FukiyaJsonParser())
  ..listen('127.0.0.1', 3333);
}

void getPeopleHandler(FukiyaContext context) {
  //String tokenData = context.
  //context.send("getPeopleHandler");
  String accessToken = context.request.session.containsKey("access_token") ? context.request.session["access_token"] : null;
  SimpleOAuth2 simpleOAuth2 = new SimpleOAuth2();
  console_auth.Credentials creds = new console_auth.Credentials(accessToken);
  simpleOAuth2.credentials = creds;
  plus.Plus plusclient = new plus.Plus(simpleOAuth2);
  plusclient.makeAuthRequests = true;
  plusclient.people.list("me", "visible").then((plus.PeopleFeed people) {
    print("people = $people");
    context.send(people.toString());
  });
}

void postConnectDataHandler(FukiyaContext context) {
  String tokenData = context.request.session.containsKey("token") ? context.request.session["token"] : null; // TODO: handle missing token
  String stateToken = context.request.session.containsKey("state_token") ? context.request.session["state_token"] : null;
  String queryStateToken = context.request.queryParameters.containsKey("state_token") ? context.request.queryParameters["state_token"] : null;
  
  if (tokenData != null) {
    context.response.statusCode = 400;
    context.send("Current user is already connected.");
    return;
  }
  
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
  context.request
  .transform(new StringDecoder())
  .listen((data) => sb.write(data), onDone: () {
    print(sb.toString());
    Map m = JSON.parse(sb.toString());
    String tokenEndpoint = 'https://accounts.google.com/o/oauth2/token';
    Map fields = {
              "grant_type": "authorization_code",
              "code": m["code"],
              // http://www.riskcompletefailure.com/2013/03/postmessage-oauth-20.html
              "redirect_uri": "postmessage",
              "client_id": "327285194570-kbpkgvfe87tlvpue69lf5krdokbepo6j.apps.googleusercontent.com",
              "client_secret": "G6KLdY07klgrDKT2jcAYVE45"
    };
    
    print("trying to post auth code from console");
    
    print("fields = $fields");
    http.Client _httpClient = new http.Client();
    _httpClient.post(tokenEndpoint, fields: fields).then((http.Response response) {
      // At this point we have the token and refresh token.
      
      var credentials = JSON.parse(response.body);
      print("credentials = ${response.body}");
      _httpClient.close();
      
      var verifyTokenUrl = 'https://www.googleapis.com/oauth2/v1/tokeninfo?access_token=${credentials["access_token"]}';
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
        
        //context.send("POST OK"); // TODO: remove this and reaplce with data we want to send back. 
        // Query the users idenity and store into database.
      });
    });
  });
}

void getIndexHandler(FukiyaContext context) {
  StringBuffer sb = new StringBuffer();
  new MD5()
  ..add(random.nextDouble().toString().codeUnits)
  ..close().forEach((s)=>sb.write(s.toRadixString(16)));
  String stateToken = sb.toString();
  context.request.session["state_token"] = stateToken;
  context.request.session.forEach((k,v)=>print("[$k: $v]"));
  
  var file = new File("./web/index.html");
  file.exists().then((exists) {
    if (exists) {
      file.readAsString().then((indexDocument) {
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