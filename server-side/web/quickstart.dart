/*
 *
 * Copyright 2013 Gerwin Sturm
 * Copyright 2013 Adam Singer
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

/*
 *
 * Adapted from Google+ Javascript Quickstart
 * https://github.com/googleplus/gplus-quickstart-javascript
 * Copyright 2013 Google Inc.
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

import "dart:html";
import "dart:convert";
import "package:js/js.dart" as js;
import "package:google_plus_v1_api/plus_v1_api_browser.dart";
import "package:google_plus_v1_api/plus_v1_api_client.dart";
import "package:google_oauth2_client/google_oauth2_browser.dart";
import "package:logging/logging.dart";

final Logger clientLogger = new Logger("client");

void main() {
  /// Setup a logger
  _setupLogger();

  /// Simple Authentication class that takes the token from the Sign-in button
  SimpleOAuth2 auth; // = new SimpleOAuth2(null);

  /// Dart Client Library for the Google+ API
  Plus plusclient; // = new Plus(auth);

  /// Stored authentication results
  Map authResultMap;

  /**
   * Gets and renders the list of people visible to this app.
   */
  void showPeople(Map peopleData) {
    PeopleFeed people = new PeopleFeed.fromJson(peopleData);

    Element visiblePeople = querySelector("#visiblePeople");
    visiblePeople.innerHtml = "";
    visiblePeople.appendHtml("Number of people visible to this app: ${people.totalItems}<br>");
    if (people.items != null) {
      people.items.forEach((Person person) {
        visiblePeople.appendHtml("<img src=\"${person.image.url}\">");
      });
    }
  }

  /**
   * Calls the server endpoint to connect the app for the user. The client
   * sends the one-time authorization code to the server and the server
   * exchanges the code for its own tokens to use for offline API access.
   * For more information, see:
   *   https://developers.google.com/+/web/signin/server-side-flow
   */
  connectServer(gplusId) {
    clientLogger.fine("gplusId = $gplusId");
    var stateToken = (querySelector("meta[name='state_token']") as MetaElement).content;
    String url = "${window.location.href}connect?state_token=${stateToken}&gplus_id=${gplusId}";
    clientLogger.fine(url);
    HttpRequest.request(url, method: "POST", sendData: JSON.encode(authResultMap),
        onProgress: (ProgressEvent e) {
          clientLogger.fine("ProgressEvent ${e.toString()}");
        }
    )
    .then((HttpRequest request) {
      clientLogger.fine("connected from POST METHOD");
      if (request.status == 401) {
        clientLogger.fine("request.responseText = ${request.responseText}");
        return;
      }

      HttpRequest.getString("${window.location.href}people").then((String data) {
        clientLogger.fine("/people = $data");
        Map peopleData = JSON.decode(data);
        showPeople(peopleData);
      });
    }).catchError((error) {
      clientLogger.fine("POST $url error ${error.toString()}");
    });
  }

  /**
   * Gets and renders the currently signed in user's profile data.
   */
  void showProfile() {
    plusclient.people.get("me").then((Person profile) {
      Element profileDiv = querySelector("#profile");
      profileDiv.appendHtml(
        "<p><img src=\"${profile.image.url}\"</p>"
      );
      profileDiv.appendHtml(
        "<p>Hello ${profile.displayName}!<br>Tagline: ${profile.tagline}<br>About: ${profile.aboutMe}</p>"
      );
      profileDiv.appendHtml(
        "<p><img src=\"${profile.cover.coverPhoto.url}\"</p>"
      );

      connectServer(profile.id);
    });
  }

  /**
   * Hides the sign in button and starts the post-authorization operations.
   *
   * @param {Map} authResult An Object which contains the access token and
   *   other authentication information.
   */
  void onSignInCallback(Map authResult) {
    querySelector("#authResult").innerHtml = "Auth Result:<br>";
    authResult.forEach((key, value) {
      querySelector("#authResult").appendHtml(" $key: $value<br>");
    });

    if (authResult["access_token"] != null) {
      querySelector("#authOps").style.display = "block";
      querySelector("#gConnect").style.display = "none";

      // Enable Authenticated requested with the granted token in the client libary
      auth = new SimpleOAuth2(authResult["access_token"],
          tokenType: authResult["token_type"]);
      /// Dart Client Library for the Google+ API
      plusclient = new Plus(auth);

      clientLogger.fine("authResult = $authResult");
      authResult.forEach((k,v) => clientLogger.fine("$k = $v"));
      authResultMap = authResult;
      plusclient.makeAuthRequests = true;

      showProfile();
    } else if (authResult["error"] != null) {
      // There was an error, which means the user is not signed in.
      // As an example, you can handle by writing to the console:
      clientLogger.fine("There was an error: ${authResult["error"]}");
      querySelector("#authResult").appendHtml("Logged out");
      querySelector("#authOps").style.display = "none";
      querySelector("#gConnect").style.display = "block";
    }
    clientLogger.fine("authResult $authResult");
  }

  /**
   * Calls the OAuth2 endpoint to disconnect the app for the user.
   */
  void disconnect(e) {
    String url = "${window.location.href}disconnect";
    HttpRequest.request(url, method: "POST")
    .then((HttpRequest request) {
      clientLogger.fine("disconnect from POST METHOD v = ${request.response}");
      if (request.status == 200) {
        Map data = JSON.decode(request.response);
        (querySelector("meta[name='state_token']") as MetaElement).content = data["state_token"];
      }

      // disable authenticated requests in the client library
      plusclient.makeAuthRequests = false;

      querySelector("#authOps").style.display = "none";
      querySelector("#profile").innerHtml = "";
      querySelector("#visiblePeople").innerHtml = "";
      querySelector("#authResult").innerHtml = "";
      querySelector("#gConnect").style.display = "block";
    });
  }

  /**
   * Calls the method that handles the authentication flow.
   *
   * @param {Object} authResult An Object which contains the access token and
   *   other authentication information.
   */
  js.scoped(() {
    js.context.onSignInCallback =  new js.Callback.many((js.Proxy authResult) {
      Map dartAuthResult = JSON.decode(
        js.context.JSON.stringify(
          authResult,
          new js.Callback.many((key, value) {
            if (key == "g-oauth-window") {
              // g-oauth-window is an object returned in the authResult
              // remove it to prevent errors in JSON.stringify
              return "";
            }
            return value;
          })
        )
      );
      onSignInCallback(dartAuthResult);
    });
  });

  /**
   * Initialization
   */
  querySelector("#disconnect").onClick.listen(disconnect);

  if (querySelector('[data-clientid="YOUR_CLIENT_ID"]') != null) {
    querySelector("#gConnect").style.display = "none";
    window.alert("""
This sample requires your OAuth credentials (client ID) from the Google APIs console:
https://code.google.com/apis/console/#:access

Find and replace YOUR_CLIENT_ID in index.html with your client ID.""");
  }

  // Load the JS library that renders and handles the Sign-in button
  ScriptElement script = new ScriptElement();
  script.async = true;
  script.type = "text/javascript";
  script.src = "https://plus.google.com/js/client:plusone.js";
  document.body.children.add(script);
}

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