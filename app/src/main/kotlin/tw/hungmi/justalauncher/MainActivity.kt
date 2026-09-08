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
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.GridView
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast

private const val ACTION_VIEW_INPUTS = "com.android.tv.action.VIEW_INPUTS"

class Tile(val label: String, val image: Drawable?, val isBanner: Boolean, val intent: Intent)

class MainActivity : Activity() {

    private lateinit var grid: GridView
    private val adapter = TileAdapter()

    private val packageReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) = load()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.main)
        grid = findViewById(R.id.grid)
        grid.adapter = adapter
        grid.setOnItemClickListener { _, _, position, _ -> launch(adapter.items[position]) }
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
        unregisterReceiver(packageReceiver)
        super.onStop()
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        grid.setSelection(0) // 再按一次 HOME 回到第一格
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        // Home 不能被 BACK 關掉
    }

    private fun load() {
        val pm = packageManager
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
        val apps = pm.queryIntentActivities(query, 0)
            .filter { it.activityInfo.packageName != packageName }
            .map { ri ->
                val banner = ri.activityInfo.loadBanner(pm)
                val launch = Intent(Intent.ACTION_MAIN)
                    .addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
                    .setComponent(ComponentName(ri.activityInfo.packageName, ri.activityInfo.name))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                Tile(ri.loadLabel(pm).toString(), banner ?: ri.loadIcon(pm), banner != null, launch)
            }
            .sortedBy { it.label.lowercase() }

        // Google TV 內建的輸入端選單（inputplayer）。沒有這個 app 的裝置就不顯示。
        // 用 PNG banner 而不是文字：畫面上只要出現任何文字，字型、排版庫、字元貼圖快取就要 ~8MB
        val inputs = Intent(ACTION_VIEW_INPUTS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val inputsTile = if (pm.resolveActivity(inputs, 0) != null)
            Tile(getString(R.string.inputs), getDrawable(R.drawable.banner_inputs), true, inputs) else null

        adapter.items = apps + listOfNotNull(inputsTile)
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
