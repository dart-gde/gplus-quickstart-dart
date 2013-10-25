/*
 * Copyright 2013 Adam Singer (financeCoding@gmail.com)
 * Copyright 2013 Gerwin Sturm
 * Copyright 2013 Google Inc. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import "package:html5lib/dom.dart";
import "package:fukiya/fukiya.dart";
import "package:google_plus_v1_api/plus_v1_api_console.dart" as plus;
import "package:google_plus_v1_api/plus_v1_api_client.dart" as plus_client;
import "package:google_oauth2_client/google_oauth2_console.dart" as console_auth;
import "package:logging/logging.dart";

final String CLIENT_ID = "327285194570-kbpkgvfe87tlvpue69lf5krdokbepo6j.apps.googleusercontent.com";
final String CLIENT_SECRET = "G6KLdY07klgrDKT2jcAYVE45";

final String TOKENINFO_URL = "https://www.googleapis.com/oauth2/v1/tokeninfo";
final String TOKEN_ENDPOINT = 'https://accounts.google.com/o/oauth2/token';
final String TOKEN_REVOKE_ENDPOINT = 'https://accounts.google.com/o/oauth2/revoke';

final String INDEX_HTML = "./web/index.html";
final Random random = new Random();
final Logger serverLogger = new Logger("server");

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

/**
 * Revoke current user's token and reset their session.
 */
void postDisconnectHandler(FukiyaContext context) {
  serverLogger.fine("postDisconnectHandler");
  serverLogger.fine("context.request.session = ${context.request.session}");

  String tokenData = context.request.session.containsKey("access_token") ? context.request.session["access_token"] : null;
  if (tokenData == null) {
    context.response.statusCode = 401;
    context.send("Current user not connected.");
    return;
  }

  final String revokeTokenUrl = "${TOKEN_REVOKE_ENDPOINT}?token=${tokenData}";
  context.request.session.remove("access_token");

  new http.Client()..get(revokeTokenUrl).then((http.Response response) {
    serverLogger.fine("GET ${revokeTokenUrl}");
    serverLogger.fine("Response = ${response.body}");
    context.request.session["state_token"] = _createStateToken();
    Map data = {
                "state_token": context.request.session["state_token"],
                "message" : "Successfully disconnected."
                };
    context.send(JSON.encode(data));
  });
}

/**
 * Get list of people user has shared with this app.
 */
void getPeopleHandler(FukiyaContext context) {
  serverLogger.fine("getPeopleHandler");
  String accessToken = context.request.session.containsKey("access_token") ? context.request.session["access_token"] : null;
  console_auth.SimpleOAuth2Console simpleOAuth2 =
      new console_auth.SimpleOAuth2Console(CLIENT_ID, CLIENT_SECRET, accessToken);
  plus.Plus plusclient = new plus.Plus(simpleOAuth2);
  plusclient.makeAuthRequests = true;
  plusclient.people.list("me", "visible").then((plus_client.PeopleFeed people) {
    serverLogger.fine("/people = $people");
    context.send(people.toString());
  });
}

/**
 * Upgrade given auth code to token, and store it in the session.
 * POST body of request should be the authorization code.
 * Example URI: /connect?state=...&gplus_id=...
 */
void postConnectDataHandler(FukiyaContext context) {
  serverLogger.fine("postConnectDataHandler");
  String tokenData = context.request.session.containsKey("access_token") ? context.request.session["access_token"] : null; // TODO: handle missing token
  String stateToken = context.request.session.containsKey("state_token") ? context.request.session["state_token"] : null;
  String queryStateToken = context.request.uri.queryParameters.containsKey("state_token") ? context.request.uri.queryParameters["state_token"] : null;

  // Check if the token already exists for this session.
  if (tokenData != null) {
    context.send("Current user is already connected.");
    return;
  }

  // Check if any of the needed token values are null or mismatched.
  if (stateToken == null || queryStateToken == null || stateToken != queryStateToken) {
    context.response.statusCode = 401;
    context.send("Invalid state parameter.");
    return;
  }

  // Normally the state would be a one-time use token, however in our
  // simple case, we want a user to be able to connect and disconnect
  // without reloading the page.  Thus, for demonstration, we don't
  // implement this best practice.
  context.request.session.remove("state_token");

  String gPlusId = context.request.uri.queryParameters["gplus_id"];
  StringBuffer sb = new StringBuffer();
  // Read data from request.
  context.request
  .transform(new Utf8Decoder())
  .listen((data) => sb.write(data), onDone: () {
    serverLogger.fine("context.request.listen.onDone = ${sb.toString()}");
    Map requestData = JSON.decode(sb.toString());

    Map fields = {
              "grant_type": "authorization_code",
              "code": requestData["code"],
              // http://www.riskcompletefailure.com/2013/03/postmessage-oauth-20.html
              "redirect_uri": "postmessage",
              "client_id": CLIENT_ID,
              "client_secret": CLIENT_SECRET
    };

    serverLogger.fine("fields = $fields");
    http.Client _httpClient = new http.Client();
    _httpClient.post(TOKEN_ENDPOINT, fields: fields).then((http.Response response) {
      // At this point we have the token and refresh token.
      var credentials = JSON.decode(response.body);
      serverLogger.fine("credentials = ${response.body}");
      _httpClient.close();

      var verifyTokenUrl = '${TOKENINFO_URL}?access_token=${credentials["access_token"]}';
      new http.Client()
      ..get(verifyTokenUrl).then((http.Response response)  {
        serverLogger.fine("response = ${response.body}");

        var verifyResponse = JSON.decode(response.body);
        String userId = verifyResponse.containsKey("user_id") ? verifyResponse["user_id"] : null;
        String accessToken = credentials.containsKey("access_token") ? credentials["access_token"] : null;
        if (userId != null && userId == gPlusId && accessToken != null) {
          context.request.session["access_token"] = accessToken;
          context.send("POST OK");
        } else {
          context.response.statusCode = 401;
          context.send("POST FAILED ${userId} != ${gPlusId}");
        }
      });
    });
  });
}

/**
 * Creating state token based on random number.
 */
String _createStateToken() {
  StringBuffer stateTokenBuffer = new StringBuffer();
  new MD5()
  ..add(random.nextDouble().toString().codeUnits)
  ..close().forEach((int s) => stateTokenBuffer.write(s.toRadixString(16)));
  String stateToken = stateTokenBuffer.toString();
  return stateToken;
}

/**
 * Sends the client a index file with state token and starts the client
 * side authentication process.
 */
void getIndexHandler(FukiyaContext context) {
  serverLogger.fine("getIndexHandler");
  // Create a state token.
  context.request.session["state_token"] = _createStateToken();

  // Readin the index file and add state token into the meta element.
  var file = new File(INDEX_HTML);
  file.exists().then((bool exists) {
    if (exists) {
      file.readAsString().then((String indexDocument) {
        Document doc = new Document.html(indexDocument);
        Element metaState = new Element.html('<meta name="state_token" content="${context.request.session["state_token"]}">');
        doc.head.children.add(metaState);
        context.response.write(doc.outerHtml);
        context.response.done.catchError((e) => serverLogger.fine("File Response error: ${e}"));
        context.response.close();
      }, onError: (error) => serverLogger.fine("error = $error"));
    } else {
      context.response.statusCode = 404;
      context.response.close();
    }
  });
}

/**
 * Logger configuration.
 */
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