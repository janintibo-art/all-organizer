#!/usr/bin/env python3
"""Injecte les permissions et reglages Android dans les fichiers generes par
`flutter create`. Execute automatiquement par GitHub Actions avant le build APK.
Le script est idempotent : on peut le relancer sans risque.
"""

import glob
import os
import re
import sys

MANIFEST = os.path.join("android", "app", "src", "main", "AndroidManifest.xml")

GROOVY_SNIPPET = """
// Force chaque module de plugin a compiler contre le SDK 36 (ajout automatique)
subprojects {
    def forceSdk = {
        if (project.hasProperty('android')) {
            project.android.compileSdkVersion 36
        }
    }
    if (project.state.executed) {
        forceSdk()
    } else {
        project.afterEvaluate { forceSdk() }
    }
}
"""

KOTLIN_SNIPPET = """
// Force chaque module de plugin a compiler contre le SDK 36 (ajout automatique)
subprojects {
    val forceSdk = {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                androidExt.javaClass
                    .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(androidExt, 36)
            } catch (e: Exception) {
            }
        }
    }
    // Un sous-projet deja evalue refuse afterEvaluate : on agit directement.
    if (state.executed) {
        forceSdk()
    } else {
        afterEvaluate { forceSdk() }
    }
}
"""

PERMISSIONS = """    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29"/>
    <uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
"""


def patch_manifest():
    """Insere les permissions avant la balise <application>.

    On travaille en expression reguliere plutot qu'en remplacement de texte
    exact : l'indentation du gabarit Flutter change d'une version a l'autre,
    et un remplacement rate passait inapercu — l'application se retrouvait
    alors sans acces reseau ni stockage.
    """
    if not os.path.exists(MANIFEST):
        print("ERREUR : manifeste introuvable :", MANIFEST)
        return False

    with open(MANIFEST, "r", encoding="utf-8") as f:
        content = f.read()

    if "MANAGE_EXTERNAL_STORAGE" not in content:
        content, count = re.subn(
            r"([ \t]*)<application",
            PERMISSIONS + r"\1<application",
            content,
            count=1,
        )
        if count == 0:
            print("ERREUR : balise <application> introuvable dans le manifeste.")
            return False

    if "requestLegacyExternalStorage" not in content:
        content = re.sub(
            r"<application",
            '<application\n        android:requestLegacyExternalStorage="true"',
            content,
            count=1,
        )

    content = re.sub(
        r'android:label="[^"]*"', 'android:label="All Organizer"', content, count=1
    )

    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(content)

    # Verification explicite : sans ces lignes, l'application est inutilisable.
    required = [
        "android.permission.INTERNET",
        "android.permission.MANAGE_EXTERNAL_STORAGE",
    ]
    missing = [r for r in required if r not in content]
    if missing:
        print("ERREUR : permissions absentes apres patch :", missing)
        return False

    print("Manifeste mis a jour. Permissions presentes.")
    print("----- AndroidManifest.xml -----")
    print(content)
    print("-------------------------------")
    return True


SERVICE_AUDIO = """
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>

        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
"""


def patch_service_audio():
    """Declare le service de lecture en arriere-plan.

    Sans lui, la musique s'arrete des que l'ecran s'eteint et aucune
    commande n'apparait sur l'ecran verrouille.
    """
    if not os.path.exists(MANIFEST):
        return False
    with open(MANIFEST, "r", encoding="utf-8") as f:
        content = f.read()

    if "com.ryanheise.audioservice.AudioService" in content:
        return True

    content, count = re.subn(r"(\s*)</application>",
                             SERVICE_AUDIO + r"\1</application>",
                             content, count=1)
    if count == 0:
        print("ERREUR : balise </application> introuvable.")
        return False

    with open(MANIFEST, "w", encoding="utf-8") as f:
        f.write(content)
    print("Service de lecture declare.")
    return True


def patch_main_activity():
    """Fait heriter MainActivity de AudioServiceActivity.

    audio_service l'exige pour que le service de lecture s'attache
    correctement a l'activite. Sans ca, l'initialisation echoue au
    demarrage et l'application reste sur un ecran vide.
    """
    trouves = glob.glob(
        os.path.join("android", "app", "src", "main", "**", "MainActivity.kt"),
        recursive=True)
    trouves += glob.glob(
        os.path.join("android", "app", "src", "main", "**", "MainActivity.java"),
        recursive=True)

    if not trouves:
        print("ATTENTION : MainActivity introuvable.")
        return False

    for chemin in trouves:
        with open(chemin, "r", encoding="utf-8") as f:
            contenu = f.read()

        if "AudioServiceActivity" in contenu:
            print("MainActivity deja adaptee :", chemin)
            continue

        contenu = contenu.replace(
            "import io.flutter.embedding.android.FlutterActivity",
            "import com.ryanheise.audioservice.AudioServiceActivity")
        contenu = contenu.replace(
            "import io.flutter.embedding.android.FlutterActivity;",
            "import com.ryanheise.audioservice.AudioServiceActivity;")
        contenu = contenu.replace("FlutterActivity()", "AudioServiceActivity()")
        contenu = contenu.replace("extends FlutterActivity",
                                  "extends AudioServiceActivity")

        with open(chemin, "w", encoding="utf-8") as f:
            f.write(contenu)
        print("MainActivity adaptee :", chemin)
        print("---")
        print(contenu)
        print("---")
    return True


def patch_gradle():
    for name in ("build.gradle", "build.gradle.kts"):
        path = os.path.join("android", "app", name)
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        # minSdk : requis par audio_service et permission_handler
        content = re.sub(r"minSdkVersion\s+flutter\.minSdkVersion", "minSdkVersion 23", content)
        content = re.sub(r"minSdk\s*=\s*flutter\.minSdkVersion", "minSdk = 23", content)
        content = re.sub(r"minSdk\s+flutter\.minSdkVersion", "minSdk 23", content)

        # compileSdk : file_picker et flutter_plugin_android_lifecycle exigent 36
        content = re.sub(r"compileSdkVersion\s+flutter\.compileSdkVersion", "compileSdkVersion 36", content)
        content = re.sub(r"compileSdk\s*=\s*flutter\.compileSdkVersion", "compileSdk = 36", content)
        content = re.sub(r"compileSdk\s+flutter\.compileSdkVersion", "compileSdk 36", content)
        content = re.sub(r"compileSdk\s*=\s*3[0-5]\b", "compileSdk = 36", content)

        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        print("Gradle mis a jour :", path)
    return True




MARKER = "ajout automatique"


def patch_root_gradle():
    """Certains plugins se compilent contre un SDK trop ancien.
    On impose le SDK 36 a tous les sous-projets depuis le build racine."""
    for name, snippet in (
        ("build.gradle", GROOVY_SNIPPET),
        ("build.gradle.kts", KOTLIN_SNIPPET),
    ):
        path = os.path.join("android", name)
        if not os.path.exists(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
        if MARKER in content:
            print("Build racine deja patche :", path)
            continue
        with open(path, "a", encoding="utf-8") as f:
            f.write(snippet)
        print("Build racine mis a jour :", path)
    return True


if __name__ == "__main__":
    ok = patch_manifest()
    ok = patch_service_audio() and ok
    ok = patch_main_activity() and ok
    patch_gradle()
    patch_root_gradle()
    sys.exit(0 if ok else 1)
