import "dart:html";
import "dart:js" as js;
import "package:google_plus_v1_api/plus_v1_api_browser.dart";
import "package:google_plus_v1_api/plus_v1_api_client.dart";
import "package:google_oauth2_client/google_oauth2_browser.dart";

void main() {

  SimpleOAuth2 auth;
  Plus plusclient;
  
  /**
   * Gets and renders the list of people visible to this app.
   */
  void showPeople() {
    plusclient.people.list("me", "visible").then((PeopleFeed people) {
      Element visiblePeople = querySelector("#visiblePeople");
      visiblePeople.innerHtml = "";
      visiblePeople.appendHtml("Number of people visible to this app: ${people.totalItems}<br>");
      if (people.items != null) {
        people.items.forEach((Person person) {
          visiblePeople.appendHtml("<img src=\"${person.image.url}\">");
        });
      }
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
    });
  }

  /**
   * Hides the sign in button and starts the post-authorization operations.
   *
   * @param {Map} authResult An Object which contains the access token and
   *   other authentication information.
   */
  void onSignInCallback(js.JsObject authResult) {
    querySelector("#authResult").innerHtml = "Auth Result:<br>";

    var keys = js.context["Object"].callMethod("keys", [authResult]);
    
    keys.forEach((key) {
      querySelector("#authResult").appendHtml("$key: ${authResult[key]}<br>");
    });
    
    if (authResult["access_token"] != null) {
      querySelector("#authOps").style.display = "block";
      querySelector("#gConnect").style.display = "none";

      // Simple Authentication class that takes the token from the Sign-in button
      auth = new SimpleOAuth2(authResult["access_token"], tokenType: authResult["token_type"]);
      // Dart Client Library for the Google+ API
      plusclient = new Plus(auth);
      
      // Enable Authenticated requested with the granted token in the client libary
      plusclient.makeAuthRequests = true;

      showProfile();
      showPeople();
    } else if (authResult["error"] != null) {
      // There was an error, which means the user is not signed in.
      // As an example, you can handle by writing to the console:
      print("There was an error: ${authResult["error"]}");
      querySelector("#authResult").appendHtml("Logged out");
      querySelector("#authOps").style.display = "none";
      querySelector("#gConnect").style.display = "block";
    }
    print("authResult $authResult");
  }

  /**
   * Calls the OAuth2 endpoint to disconnect the app for the user.
   */
  void disconnect(e) {
    // JSONP workaround because the accounts.google.com endpoint doesn't allow CORS
    js.context["myJsonpCallback"] = ([jsonData]) {
      print("revoke response: $jsonData");

      // disable authenticated requests in the client library
      plusclient.makeAuthRequests = false;

      querySelector("#authOps").style.display = "none";
      querySelector("#profile").innerHtml = "";
      querySelector("#visiblePeople").innerHtml = "";
      querySelector("#authResult").innerHtml = "";
      querySelector("#gConnect").style.display = "block";
    };

    ScriptElement script = new Element.tag("script");
    script.src = "https://accounts.google.com/o/oauth2/revoke?token=${auth.token}&callback=myJsonpCallback";
    document.body.children.add(script);
  }

  /**
   * Calls the method that handles the authentication flow.
   *
   * @param {Object} authResult An Object which contains the access token and
   *   other authentication information.
   */
  js.context["onSignInCallback"] = onSignInCallback;

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
