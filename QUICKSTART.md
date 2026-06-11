In `app/UniFiCameraPopup`:

```
$ ./scripts/build-release.sh
$ git add AppConfig.swift ../../server/version.json ../../server/public/app.zip
$ git commit -m "Release build N" && git push
```

Install locally (optional):

```
$ cp -Rf ".build/Build/Products/Release/UniFi Camera Popup.app" /Applications/
```

On the server: `git pull`
