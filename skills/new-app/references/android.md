# Android (Kotlin, Jetpack Compose)

A single `app` module that uses the Gradle Kotlin DSL and a version catalog. The UI is Compose with Material 3, and dependency
injection is manual through `AppContainer` (no Hilt). The API is called with Retrofit and kotlinx.serialization, and its models
are written by hand to match `openapi/api.json`. Sign-in uses AppAuth against Cognito managed login (authorization code + PKCE).

## Contents
- [Layout](#layout)
- [Gradle](#gradle)
- [Manifest and resources](#manifest-and-resources)
- [Auth](#auth)
- [API and DI](#api-and-di)
- [Screens](#screens)
- [Tests and done criteria](#tests-and-done-criteria)

## Layout

```
android/
  settings.gradle.kts  build.gradle.kts  gradle.properties  gradlew  gradlew.bat
  gradle/libs.versions.toml  gradle/wrapper/gradle-wrapper.{jar,properties}
  app/build.gradle.kts  app/proguard-rules.pro
  app/src/main/AndroidManifest.xml
  app/src/main/java/com/<company>/<app>/
    <App>Application.kt  AppContainer.kt  MainActivity.kt
    data/ AccountRepository.kt  TermsAcceptance.kt
    data/api/ <App>Api.kt  Models.kt  ApiJson.kt  ApiErrors.kt  AuthInterceptor.kt
    data/auth/ AuthManager.kt
    ui/ <App>App.kt (NavHost)  AppContainerLocal.kt  theme/  signin/  account/
    util/ Browser.kt  Format.kt
  app/src/debug/res/xml/network_security_config.xml
  app/src/main/res/ values/{strings,colors,themes}.xml  xml/network_security_config.xml  mipmap-anydpi-v26/  drawable/
  app/src/test/java/com/<company>/<app>/...
```

**Gradle wrapper:** generate it with `gradle wrapper --gradle-version 9.8.2` in `android/`. Use `gradle` from PATH if it's there,
or else a cached distribution at `~/.gradle/wrapper/dists/gradle-9.8.2-bin/*/gradle-9.8.2/bin/gradle`, which any earlier Gradle
project leaves behind. If neither exists, write `gradle-wrapper.properties` (below) and record in the report that the wrapper is
missing. Opening the project in Android Studio creates it. Never write the jar by hand.

**SDK location:** if `ANDROID_HOME` isn't set, write a git-ignored `local.properties` with `sdk.dir=` and the SDK path using
**forward slashes** (on Windows, usually `C:/Users/<user>/AppData/Local/Android/Sdk`). In a properties file a backslash is an escape
character, so `C:\Users\...` silently becomes a wrong path.

## Gradle

```properties
# gradle/wrapper/gradle-wrapper.properties
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-9.8.2-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

`settings.gradle.kts` uses the standard `pluginManagement` (google with the `com.android.*`, `com.google.*` and `androidx.*` group filters, then
mavenCentral and gradlePluginPortal), `dependencyResolutionManagement` with `FAIL_ON_PROJECT_REPOS` (google and mavenCentral),
`rootProject.name = "<App>"` and `include(":app")`. The root `build.gradle.kts` declares the three plugins below with `apply false`.

```toml
# gradle/libs.versions.toml (core; modules add entries)
[versions]
agp = "9.5.1"
kotlin = "2.4.21"
coreKtx = "1.19.1"
activityCompose = "1.13.0"
lifecycle = "2.11.0"
navigationCompose = "2.10.2"
composeBom = "2026.09.00"
browser = "1.10.0"
appauth = "0.11.1"
retrofit = "2.11.0"
okhttp = "4.12.0"
kotlinxSerialization = "1.12.0"
coroutines = "1.11.0"
junit = "4.13.2"

[libraries]
androidx-core-ktx = { module = "androidx.core:core-ktx", version.ref = "coreKtx" }
androidx-activity-compose = { module = "androidx.activity:activity-compose", version.ref = "activityCompose" }
androidx-lifecycle-runtime-compose = { module = "androidx.lifecycle:lifecycle-runtime-compose", version.ref = "lifecycle" }
androidx-lifecycle-viewmodel-compose = { module = "androidx.lifecycle:lifecycle-viewmodel-compose", version.ref = "lifecycle" }
androidx-navigation-compose = { module = "androidx.navigation:navigation-compose", version.ref = "navigationCompose" }
androidx-browser = { module = "androidx.browser:browser", version.ref = "browser" }
androidx-compose-bom = { module = "androidx.compose:compose-bom", version.ref = "composeBom" }
androidx-compose-ui = { module = "androidx.compose.ui:ui" }
androidx-compose-ui-tooling = { module = "androidx.compose.ui:ui-tooling" }
androidx-compose-ui-tooling-preview = { module = "androidx.compose.ui:ui-tooling-preview" }
androidx-compose-material3 = { module = "androidx.compose.material3:material3" }
androidx-compose-material-icons-extended = { module = "androidx.compose.material:material-icons-extended" }
appauth = { module = "net.openid:appauth", version.ref = "appauth" }
retrofit = { module = "com.squareup.retrofit2:retrofit", version.ref = "retrofit" }
retrofit-kotlinx-serialization = { module = "com.squareup.retrofit2:converter-kotlinx-serialization", version.ref = "retrofit" }
okhttp = { module = "com.squareup.okhttp3:okhttp", version.ref = "okhttp" }
kotlinx-serialization-json = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version.ref = "kotlinxSerialization" }
kotlinx-coroutines-android = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-android", version.ref = "coroutines" }
junit = { module = "junit:junit", version.ref = "junit" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
kotlin-compose = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }
```

AGP 9 has built-in Kotlin support, so there is no `org.jetbrains.kotlin.android` plugin.

```properties
# gradle.properties
org.gradle.jvmargs=-Xmx4g -Dfile.encoding=UTF-8
org.gradle.parallel=true
org.gradle.caching=true
org.gradle.tooling.parallel=true
android.useAndroidX=true
android.nonTransitiveRClass=true

# App configuration. Override any of these in ~/.gradle/gradle.properties or with -P on the command line.
# The Cognito app client must list <app>.redirectUri as a callback URL and <app>.logoutUri as a sign-out URL,
# and the API's Auth:ClientIds must include <app>.cognitoClientId.
<app>.cognitoRegion=<region>
<app>.cognitoUserPoolId=
<app>.cognitoDomain=<app>.auth.<region>.amazoncognito.com
<app>.cognitoClientId=
<app>.redirectUri=com.<company>.<app>://callback
<app>.logoutUri=com.<company>.<app>://signout
<app>.webUrl=https://<domain>
# The emulator reaches the host's localhost through `adb reverse tcp:5142 tcp:5142`.
<app>.apiUrl.debug=http://localhost:5142/
<app>.apiUrl.release=https://api.<domain>/
```

```kotlin
// app/build.gradle.kts
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

fun <app>Property(name: String): String =
    providers.gradleProperty("<app>.$name").orNull ?: error("Missing gradle property <app>.$name")

fun quoted(value: String) = "\"$value\""

// Release signing comes from the CI pipeline; without it, release builds are unsigned.
val releaseKeystore = providers.environmentVariable("<APP>_KEYSTORE_FILE").orNull

android {
    namespace = "com.<company>.<app>"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.<company>.<app>"
        minSdk = 26
        targetSdk = 37
        // CI passes -P<app>.versionCode=<build id> so every test build installs over the last one.
        versionCode = providers.gradleProperty("<app>.versionCode").orNull?.toInt() ?: 1
        versionName = "0.1.0"

        // AppAuth's redirect activity listens on this scheme; see the override in AndroidManifest.xml.
        manifestPlaceholders["appAuthRedirectScheme"] = "com.<company>.<app>"

        buildConfigField("String", "COGNITO_REGION", quoted(<app>Property("cognitoRegion")))
        buildConfigField("String", "COGNITO_USER_POOL_ID", quoted(<app>Property("cognitoUserPoolId")))
        buildConfigField("String", "COGNITO_DOMAIN", quoted(<app>Property("cognitoDomain")))
        buildConfigField("String", "COGNITO_CLIENT_ID", quoted(<app>Property("cognitoClientId")))
        buildConfigField("String", "REDIRECT_URI", quoted(<app>Property("redirectUri")))
        buildConfigField("String", "LOGOUT_URI", quoted(<app>Property("logoutUri")))
        buildConfigField("String", "WEB_URL", quoted(<app>Property("webUrl")))
    }

    signingConfigs {
        if (releaseKeystore != null) {
            create("release") {
                storeFile = file(releaseKeystore)
                storePassword = providers.environmentVariable("<APP>_KEYSTORE_PASSWORD").get()
                keyAlias = providers.environmentVariable("<APP>_KEY_ALIAS").get()
                keyPassword = providers.environmentVariable("<APP>_KEY_PASSWORD").get()
            }
        }
    }

    buildTypes {
        debug {
            buildConfigField("String", "API_URL", quoted(<app>Property("apiUrl.debug")))
        }
        release {
            buildConfigField("String", "API_URL", quoted(<app>Property("apiUrl.release")))
            if (releaseKeystore != null) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.browser)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    debugImplementation(libs.androidx.compose.ui.tooling)
    implementation(libs.appauth)
    implementation(libs.retrofit)
    implementation(libs.retrofit.kotlinx.serialization)
    implementation(libs.okhttp)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    testImplementation(libs.junit)
}
```

`proguard-rules.pro` keeps the `@Serializable` model classes and Retrofit interfaces, using the standard kotlinx.serialization and Retrofit rules.

## Manifest and resources

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

    <queries>
        <!-- Custom Tabs browsers for sign-in and web pages. -->
        <intent>
            <action android:name="android.support.customtabs.action.CustomTabsService" />
        </intent>
    </queries>

    <application
        android:name=".<App>Application"
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:networkSecurityConfig="@xml/network_security_config"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/Theme.<App>">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
            <!-- Cognito's logout endpoint returns here, which closes the Custom Tab and resumes the app. -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:host="signout" android:scheme="com.<company>.<app>" />
            </intent-filter>
        </activity>

        <!-- Narrow AppAuth's redirect receiver to the callback host so it doesn't also claim the sign-out redirect. -->
        <activity
            android:name="net.openid.appauth.RedirectUriReceiverActivity"
            android:exported="true"
            tools:node="replace">
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:host="callback" android:scheme="${appAuthRedirectScheme}" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

Network security: `main/res/xml/network_security_config.xml` sets `<base-config cleartextTrafficPermitted="false" />`. The
`debug` source set overrides it with a `domain-config cleartextTrafficPermitted="true"` for `10.0.2.2` and `localhost`, so debug
builds can reach the local API over HTTP.

Resources: `app_name` = `<App>`. `Theme.<App>` extends `android:Theme.Material.Light.NoActionBar`, and Compose draws the real theme.
The adaptive launcher icon is a vector foreground with a single letter on a solid background, a placeholder until real artwork exists.

## Auth

```kotlin
package com.<company>.<app>.data.auth

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.edit
import com.<company>.<app>.BuildConfig
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import net.openid.appauth.AuthState
import net.openid.appauth.AuthorizationException
import net.openid.appauth.AuthorizationRequest
import net.openid.appauth.AuthorizationResponse
import net.openid.appauth.AuthorizationService
import net.openid.appauth.AuthorizationServiceConfiguration
import net.openid.appauth.ResponseTypeValues
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Signs in against Cognito managed login with the authorization code + PKCE flow (the same flow the
 * web app runs through oidc-client-ts) and keeps the tokens, refreshing them as they expire.
 */
class AuthManager(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val service = AuthorizationService(context)
    private val mutex = Mutex()

    private val tokenEndpoint = Uri.parse("https://${BuildConfig.COGNITO_DOMAIN}/oauth2/token")
    private val signInConfig = AuthorizationServiceConfiguration(
        Uri.parse("https://${BuildConfig.COGNITO_DOMAIN}/oauth2/authorize"),
        tokenEndpoint,
    )

    // Same PKCE sign-in, but opens managed login on the sign-up page.
    private val signUpConfig = AuthorizationServiceConfiguration(
        Uri.parse("https://${BuildConfig.COGNITO_DOMAIN}/signup"),
        tokenEndpoint,
    )

    private var authState: AuthState = readState()
    private val _isSignedIn = MutableStateFlow(authState.isAuthorized)
    val isSignedIn: StateFlow<Boolean> = _isSignedIn.asStateFlow()

    val email: String?
        get() = authState.parsedIdToken?.additionalClaims?.get("email") as? String

    /** The Cognito user's `sub`, which stays the same for the life of the account. */
    val userId: String?
        get() = authState.parsedIdToken?.subject

    fun signInIntent(signUp: Boolean = false): Intent {
        val request = AuthorizationRequest.Builder(
            if (signUp) signUpConfig else signInConfig,
            BuildConfig.COGNITO_CLIENT_ID,
            ResponseTypeValues.CODE,
            Uri.parse(BuildConfig.REDIRECT_URI),
        )
            .setScope(SCOPE)
            .build()
        return service.getAuthorizationRequestIntent(request)
    }

    /** Exchanges the authorization code returned to [signInIntent]'s activity result for tokens. */
    suspend fun completeSignIn(data: Intent?) {
        val response = data?.let { AuthorizationResponse.fromIntent(it) }
        if (response == null) {
            throw data?.let { AuthorizationException.fromIntent(it) } ?: SignInCancelledException()
        }

        val state = AuthState(response, null)
        val tokenResponse = suspendCancellableCoroutine { continuation ->
            service.performTokenRequest(response.createTokenExchangeRequest()) { tokens, exception ->
                if (tokens != null) {
                    continuation.resume(tokens)
                } else {
                    continuation.resumeWithException(exception ?: IllegalStateException("Token exchange failed"))
                }
            }
        }
        state.update(tokenResponse, null)

        mutex.withLock { saveState(state) }
    }

    /**
     * Returns a valid access token, refreshing it first when it has expired. Returns null when signed out;
     * a refresh token Cognito rejects (revoked or expired) signs the user out.
     */
    suspend fun freshAccessToken(): String? = mutex.withLock {
        val state = authState
        if (!state.isAuthorized) {
            return@withLock null
        }

        val (accessToken, exception) = suspendCancellableCoroutine { continuation ->
            state.performActionWithFreshTokens(service) { accessToken, _, exception ->
                continuation.resume(accessToken to exception)
            }
        }

        if (exception?.type == AuthorizationException.TYPE_OAUTH_TOKEN_ERROR) {
            saveState(AuthState())
            return@withLock null
        }

        saveState(state)
        accessToken
    }

    /**
     * Forgets the local tokens and returns Cognito's logout URL, which must be opened in the browser
     * so managed login's session cookie is cleared too; it redirects back to the app afterwards.
     */
    suspend fun signOut(): Uri {
        mutex.withLock { saveState(AuthState()) }
        return Uri.parse("https://${BuildConfig.COGNITO_DOMAIN}/logout").buildUpon()
            .appendQueryParameter("client_id", BuildConfig.COGNITO_CLIENT_ID)
            .appendQueryParameter("logout_uri", BuildConfig.LOGOUT_URI)
            .build()
    }

    private fun readState(): AuthState =
        prefs.getString(KEY_STATE, null)
            ?.let { runCatching { AuthState.jsonDeserialize(it) }.getOrNull() }
            ?: AuthState()

    private fun saveState(state: AuthState) {
        authState = state
        prefs.edit { putString(KEY_STATE, state.jsonSerializeString()) }
        _isSignedIn.value = state.isAuthorized
    }

    private companion object {
        const val PREFS_NAME = "auth"
        const val KEY_STATE = "state"
        // aws.cognito.signin.user.admin lets the API read the email and delete the account with this token.
        const val SCOPE = "aws.cognito.signin.user.admin email openid phone profile"
    }
}

class SignInCancelledException : Exception("Sign-in was cancelled.")
```

```kotlin
/** Adds the signed-in user's bearer token to API requests, refreshing it first when needed. */
class AuthInterceptor(private val authManager: AuthManager) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        // OkHttp runs interceptors on its own threads, so blocking here doesn't block the UI.
        val accessToken = runBlocking { authManager.freshAccessToken() }
        val request = if (accessToken == null) {
            chain.request()
        } else {
            chain.request().newBuilder().header("Authorization", "Bearer $accessToken").build()
        }
        return chain.proceed(request)
    }
}
```

The sign-in screen launches `authManager.signInIntent()` with `rememberLauncherForActivityResult(StartActivityForResult())`
and calls `completeSignIn(result.data)` in a coroutine. It treats `SignInCancelledException` as a quiet cancel and shows any other
exception as an error. Sign-out calls `signOut()` and opens the returned URL in a Custom Tab (`util/Browser.kt`).

## API and DI

```kotlin
/**
 * The JSON setup for API requests and responses. Note that values equal to a property's default aren't encoded,
 * so request models shouldn't give defaults to fields the API requires.
 */
val apiJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    coerceInputValues = true
}
```

```kotlin
interface <App>Api {
    /** Registers the signed-in user on first call and returns them on every call. */
    @POST("users")
    suspend fun logUser(): UserResponse

    @PUT("users/me")
    suspend fun updateMe(@Body request: UserUpdateRequest): UserResponse

    /** Permanently deletes the account and everything linked to it, including the sign-in. */
    @DELETE("users/me")
    suspend fun deleteMe()
}
```

`Models.kt` contains `@Serializable` data classes that mirror the OpenAPI schemas (`UserResponse(publicId: String, email: String? = null, name: String? = null)`,
`UserUpdateRequest(name: String?)`). Enums use `@SerialName` with the API's string values. `ApiErrors.kt` turns `HttpException` into a
message a user can read: the response body for 400s with a string body, and generic text otherwise.

```kotlin
/** App-wide singletons, created once by [<App>Application]. */
class AppContainer(context: Context) {
    val authManager = AuthManager(context)
    val termsAcceptance = TermsAcceptance(context)

    val okHttpClient: OkHttpClient = OkHttpClient.Builder()
        .addInterceptor(AuthInterceptor(authManager))
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .build()

    val api: <App>Api = Retrofit.Builder()
        .baseUrl(BuildConfig.API_URL)
        .client(okHttpClient)
        .addConverterFactory(apiJson.asConverterFactory("application/json".toMediaType()))
        .build()
        .create(<App>Api::class.java)

    val accountRepository = AccountRepository(api)
}
```

`<App>Application : Application` creates `AppContainer` in `onCreate`. `ui/AppContainerLocal.kt` provides it through a
`staticCompositionLocalOf`, so screens and ViewModel factories can reach it. `AccountRepository` wraps `logUser`, `updateMe` and `deleteMe`
and holds the current `UserResponse` in a `StateFlow`.

## Screens

`MainActivity` (`enableEdgeToEdge`, `setContent { <App>Theme { <App>App() } }`) → `<App>App` collects `authManager.isSignedIn`:
- Signed out → `SignInScreen`: the app name, Sign in and Create account (`signInIntent(signUp = true)`) buttons, and links to the privacy policy and terms on the web.
- Signed in but terms not accepted → `TermsScreen`. `TermsAcceptance` stores acceptance in SharedPreferences keyed by the user's `sub` and the terms version, and uses the same version string as the web.
- Signed in with terms accepted → call `accountRepository.logUser()` once for each `sub`, then show a `NavHost` with a bottom bar: Home (placeholder) and Account.
  - `AccountScreen`: the email, Profile, Privacy Policy and Terms (Custom Tab to the web pages), and Sign out.
  - `ProfileScreen`: edits the name, and deletes the account after a confirm dialog, then signs out.

Each screen has a ViewModel when it loads or saves data. ViewModels expose `StateFlow<UiState>`, and screens collect them with `collectAsStateWithLifecycle`.
`ui/theme/Theme.kt` has a Material 3 color scheme from one brand color, plus dynamic color on Android 12+.

## Tests and done criteria

JUnit tests cover `ApiErrors` mapping, JSON decoding of `UserResponse` with missing and unknown fields through `apiJson`, `TermsAcceptance` versioning
(pure logic, so keep the SharedPreferences access behind a small interface), and `util/Format`.

`.gitignore` covers `.gradle/`, `build/`, `local.properties`, `.idea/`, `*.iml`, `.kotlin/` and `*.jks`.

**Done when:** `./gradlew testDebugUnitTest assembleDebug` succeeds. If there's no Android SDK, check by reading instead: every class
in the manifest exists, every `R.` reference has a resource, and every catalog alias used is defined. Then report it as not built.
