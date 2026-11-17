package sh.nullnet.lightwallet

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var links: MethodChannel? = null

    /** The `null:` link the app was started with, until Dart asks for it. */
    private var initialLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // No screenshots, screen recording or recents preview: the app shows
        // recovery phrases, balances and addresses.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        // A relaunch from recents replays the old intent; it is not a new link.
        if (savedInstanceState == null) initialLink = paymentLink(intent)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        links = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                if (call.method == "initialLink") {
                    result.success(initialLink)
                    initialLink = null
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        paymentLink(intent)?.let { links?.invokeMethod("link", it) }
    }

    /** The intent's `null:` URI, if it is a payment link of sane length. */
    private fun paymentLink(intent: Intent?): String? =
        intent
            ?.takeIf { it.action == Intent.ACTION_VIEW }
            ?.dataString
            ?.takeIf { it.startsWith("null:", ignoreCase = true) && it.length <= MAX_LINK_CHARS }

    private companion object {
        const val CHANNEL = "sh.nullnet.lightwallet/links"

        /** `maxPaymentUriChars` in lib/src/core/payment_uri.dart. */
        const val MAX_LINK_CHARS = 4096
    }
}
