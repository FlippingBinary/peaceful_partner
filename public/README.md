# Web server resources

These files are deployed to a web server so the mobile app can load them from a
remote resource instead of a local resource. It's a weird workaround, I know,
but that's how this works. The app uses a webview to load the resource so that
EmotionAI can monitor the user's affect. If this resource doesn't load, the
app will still work without the ability to interrupt the user's heightened
emotional states.
