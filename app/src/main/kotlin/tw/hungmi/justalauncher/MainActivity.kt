package tw.hungmi.justalauncher

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.drawable.Drawable
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.GridView
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast

private const val ACTION_VIEW_INPUTS = "com.android.tv.action.VIEW_INPUTS"
private const val KEY_ORDER = "order"
private const val KEY_INPUTS = "inputs"

class Tile(val key: String, val label: String, val image: Drawable?, val isBanner: Boolean, val intent: Intent)

class MainActivity : Activity() {

    private lateinit var grid: GridView
    private val adapter = TileAdapter()

    // 長按 OK 進入移動模式，moving 是正在移的那格；-1 = 沒在移
    private var moving = -1
    private var confirmDown = false

    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = load()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.main)
        grid = findViewById(R.id.grid)
        grid.adapter = adapter
        grid.setOnItemClickListener { _, _, position, _ -> launch(adapter.items[position]) }
        grid.setOnItemLongClickListener { _, _, position, _ -> startMove(position); true }
        load()
    }

    override fun onStart() {
        super.onStart()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REMOVED)
            addAction(Intent.ACTION_PACKAGE_CHANGED)
            addDataScheme("package")
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(packageReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(packageReceiver, filter)
        }
    }

    override fun onStop() {
        endMove()
        unregisterReceiver(packageReceiver)
        super.onStop()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        endMove()
        grid.setSelection(0) // 再按一次 HOME 回到第一格
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Home 不能被 BACK 關掉
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (moving < 0) return super.dispatchKeyEvent(event)
        val down = event.action == KeyEvent.ACTION_DOWN
        val last = adapter.count - 1
        val cols = grid.numColumns.coerceAtLeast(1)
        when (event.keyCode) {
            KeyEvent.KEYCODE_DPAD_LEFT -> if (down && moving > 0) moveTo(moving - 1)
            KeyEvent.KEYCODE_DPAD_RIGHT -> if (down && moving < last) moveTo(moving + 1)
            KeyEvent.KEYCODE_DPAD_UP -> if (down && moving >= cols) moveTo(moving - cols)
            KeyEvent.KEYCODE_DPAD_DOWN -> if (down && moving / cols < last / cols) moveTo(minOf(moving + cols, last))
            KeyEvent.KEYCODE_DPAD_CENTER, KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER, KeyEvent.KEYCODE_BACK ->
                // 長按進來時手還按著 OK，那次放開不算；在移動模式裡重新按一次才放下
                if (down && event.repeatCount == 0) confirmDown = true
                else if (!down && confirmDown) endMove()
            else -> return super.dispatchKeyEvent(event)
        }
        return true
    }

    private fun startMove(position: Int) {
        moving = position
        confirmDown = false
        adapter.notifyDataSetChanged() // 那格變半透明
    }

    private fun moveTo(position: Int) {
        adapter.items = adapter.items.toMutableList().apply { add(position, removeAt(moving)) }
        moving = position
        adapter.notifyDataSetChanged()
        grid.setSelection(position)
    }

    private fun endMove() {
        if (moving < 0) return
        moving = -1
        adapter.notifyDataSetChanged()
        getPreferences(MODE_PRIVATE).edit()
            .putString(KEY_ORDER, adapter.items.joinToString("\n") { it.key })
            .apply()
    }

    private fun load() {
        endMove() // 移動中裝了或移除 app：先存目前的順序再重排
        val pm = packageManager
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
        val apps = pm.queryIntentActivities(query, 0)
            .filter { it.activityInfo.packageName != packageName }
            .map { ri ->
                val component = ComponentName(ri.activityInfo.packageName, ri.activityInfo.name)
                val banner = ri.activityInfo.loadBanner(pm)
                val launch = Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
                    .setComponent(component)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                Tile(component.flattenToShortString(), ri.loadLabel(pm).toString(), banner ?: ri.loadIcon(pm), banner != null, launch)
            }
            .sortedBy { it.label.lowercase() }

        // Google TV 內建的輸入端選單（inputplayer）。沒有這個 app 的裝置就不顯示。
        // 用 PNG banner 而不是文字：畫面上只要出現任何文字，字型、排版庫、字元貼圖快取就要 ~8MB
        val inputs = Intent(ACTION_VIEW_INPUTS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val inputsTile = if (pm.resolveActivity(inputs, 0) != null)
            Tile(KEY_INPUTS, getString(R.string.inputs), getDrawable(R.drawable.banner_inputs), true, inputs) else null

        // 移過的照存檔順序；沒移過的（例如之後新裝的 app）排在最後，彼此照字母
        val saved = getPreferences(MODE_PRIVATE).getString(KEY_ORDER, null)?.split('\n').orEmpty()
        val rank = saved.withIndex().associate { (i, key) -> key to i }
        adapter.items = (apps + listOfNotNull(inputsTile)).sortedBy { rank[it.key] ?: Int.MAX_VALUE }
        adapter.notifyDataSetChanged()
    }

    private fun launch(tile: Tile) {
        try {
            startActivity(tile.intent)
        } catch (e: Exception) { // ActivityNotFoundException、SecurityException
            Toast.makeText(this, "${getString(R.string.launch_failed)} ${tile.label}", Toast.LENGTH_SHORT).show()
        }
    }

    private inner class TileAdapter : BaseAdapter() {
        var items: List<Tile> = emptyList()

        override fun getCount() = items.size
        override fun getItem(position: Int) = items[position]
        override fun getItemId(position: Int) = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup): View {
            val view = convertView ?: LayoutInflater.from(parent.context).inflate(R.layout.tile, parent, false)
            val tile = items[position]
            val image = view.findViewById<ImageView>(R.id.image)
            val label = view.findViewById<TextView>(R.id.label)
            image.setImageDrawable(tile.image)
            // 設在 ImageView 上：它沒有背景，半透明不用開離屏緩衝區
            image.alpha = if (position == moving) 0.5f else 1f
            if (tile.isBanner) {
                image.setPadding(0, 0, 0, 0)
                label.visibility = View.GONE
            } else {
                val pad = (18 * parent.resources.displayMetrics.density).toInt()
                image.setPadding(pad, pad, pad, pad)
                label.text = tile.label
                label.visibility = View.VISIBLE
            }
            return view
        }
    }
}
