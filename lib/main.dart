import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

void main() { runApp(const FazlakaApp()); }

class Package {
  final String name;
  final String profile;
  final int price;
  final int quotaGB;
  final int days;
  const Package({required this.name, required this.profile, required this.price, required this.quotaGB, required this.days});
}

const List<Package> packages = [
  Package(name: 'باقة 20 - 2 جيجا - 3 أيام', profile: '20', price: 20, quotaGB: 2, days: 3),
  Package(name: 'باقة 50 - 8 جيجا - 7 أيام', profile: '50', price: 50, quotaGB: 8, days: 7),
  Package(name: 'باقة 100 - 20 جيجا - 30 يوم', profile: '100', price: 100, quotaGB: 20, days: 30),
];

class FazlakaApp extends StatelessWidget {
  const FazlakaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fazlaka',
      theme: ThemeData(useMaterial3: true, fontFamily: 'sans-serif', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF009688))),
      home: const LoginScreen(),
    );
  }
}

class MikrotikApi {
  Socket? _sock;
  Stream<List<int>>? _broad;
  Future<void> connect(String host, int port) async {
    final sock = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    _sock = sock;
    _broad = sock.asBroadcastStream();
  }
  void _writeWord(String w) {
    final b = utf8.encode(w);
    final len = b.length;
    if (len < 0x80) {
      _sock!.add([len]);
    } else if (len < 0x4000) {
      _sock!.add([(len >> 8) | 0x80, len & 0xFF]);
    } else if (len < 0x200000) {
      _sock!.add([(len >> 16) | 0xC0, (len >> 8) & 0xFF, len & 0xFF]);
    }
    _sock!.add(b);
  }
  void _writeSentence(List<String> words) {
    for (final w in words) _writeWord(w);
    _sock!.add([0]);
  }
  Future<List<Map<String,String>>> _readSentence() async {
    final completer = Completer<List<Map<String,String>>>();
    final List<Map<String,String>> out = [];
    Map<String,String> cur = {};
    List<int> buf = [];
    StreamSubscription? sub;
    sub = _broad!.listen((data) {
      buf.addAll(data);
      int i = 0;
      while (i < buf.length) {
        int len = buf[i]; i++;
        if (len == 0) { if (cur.isNotEmpty || out.isEmpty) { out.add(Map.from(cur)); cur = {}; } continue; }
        if (len & 0x80 != 0) { if (i >= buf.length) break; len = ((len & 0x7F) << 8) | buf[i]; i++; }
        if (i + len > buf.length) break;
        final word = utf8.decode(buf.sublist(i, i+len), allowMalformed: true); i += len;
        if (word == '!done' || word == '!re' || word == '!trap' || word == '!fatal') {
          if (word != '!re') { if (cur.isNotEmpty) out.add(Map.from(cur)); cur = {}; }
          if (word == '!done') { if (!completer.isCompleted) { completer.complete(out); sub?.cancel(); } }
        } else if (word.startsWith('=')) {
          final eq = word.indexOf('=', 1);
          if (eq > 0) cur[word.substring(1, eq)] = word.substring(eq+1);
        } else if (word.startsWith('.')) {
          cur[word] = '';
        }
      }
      buf = buf.sublist(i);
    }, onError: (e){ if(!completer.isCompleted) completer.completeError(e); }, onDone: (){ if(!completer.isCompleted) completer.complete(out); });
    return completer.future.timeout(const Duration(seconds: 8), onTimeout: () => out);
  }
  Future<void> login(String user, String pass) async {
    _writeSentence(['/login', '=name=$user', '=password=$pass']);
    var res = await _readSentence();
    String? ret;
    for (var m in res) { if (m.containsKey('ret')) ret = m['ret']; }
    if (ret != null) {
      final chal = hexDecode(ret);
      final passHash = md5.convert(utf8.encode(pass)).bytes;
      final md = md5.convert([0] + chal + passHash);
      _writeSentence(['/login', '=name=$user', '=response=00${md.toString()}']);
      await _readSentence();
    }
  }
  static List<int> hexDecode(String s) { List<int> o=[]; for(int i=0;i<s.length;i+=2) o.add(int.parse(s.substring(i,i+2), radix:16)); return o; }
  Future<List<Map<String,String>>> cmd(List<String> words) async { _writeSentence(words); return _readSentence(); }
  void close(){ try{_sock?.destroy();}catch(_){} _sock=null; _broad=null; }
}

class LoginScreen extends StatefulWidget { const LoginScreen({super.key}); @override State<LoginScreen> createState()=>_LoginScreenState(); }
class _LoginScreenState extends State<LoginScreen> {
  final _ip = TextEditingController(text: '10.10.10.1');
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController(text: 'asdf4411');
  bool _showPass = false, _remember = true, _auto = false, _loading = false;
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    setState((){ _ip.text = p.getString('ip') ?? '10.10.10.1'; _user.text = p.getString('user') ?? 'admin'; _pass.text = p.getString('pass') ?? 'asdf4411'; _remember = p.getBool('remember') ?? true; _auto = p.getBool('auto') ?? false; });
    if (_auto) _doLogin();
  }
  Future<void> _doLogin() async {
    setState(()=>_loading=true);
    try {
      final api = MikrotikApi();
      await api.connect(_ip.text.trim(), 8728);
      await api.login(_user.text.trim(), _pass.text.trim());
      final p = await SharedPreferences.getInstance();
      if (_remember) { await p.setString('ip', _ip.text.trim()); await p.setString('user', _user.text.trim()); await p.setString('pass', _pass.text.trim()); }
      await p.setBool('remember', _remember); await p.setBool('auto', _auto);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_)=>HomeScreen(api: api, ip: _ip.text.trim(), user: _user.text.trim(), pass: _pass.text.trim())));
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الدخول: $e')));
    }
    if(mounted) setState(()=>_loading=false);
  }
  @override Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF0F3D3E), body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('FAZLAKA', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Color(0xFF009688))),
      const SizedBox(height: 6), const Text('إدارة هوت سبوت MikroTik', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 20),
      _field('IP الراوتر', _ip, false), const SizedBox(height: 12),
      _field('اسم المستخدم', _user, false), const SizedBox(height: 12),
      TextField(controller: _pass, obscureText: !_showPass, textAlign: TextAlign.right, decoration: InputDecoration(labelText: 'كلمة السر', border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), suffixIcon: IconButton(icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility), onPressed: ()=>setState(()=>_showPass=!_showPass)))),
      CheckboxListTile(value: _remember, onChanged: (v)=>setState(()=>_remember=v??true), title: const Text('تذكر البيانات', textDirection: TextDirection.rtl)),
      CheckboxListTile(value: _auto, onChanged: (v)=>setState(()=>_auto=v??false), title: const Text('دخول تلقائي', textDirection: TextDirection.rtl)),
      const SizedBox(height: 10),
      ElevatedButton(onPressed: _loading?null:_doLogin, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF009688), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('دخول', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
    ]))))));
  }
  Widget _field(String label, TextEditingController c, bool obscure) => TextField(controller: c, textAlign: TextAlign.right, decoration: InputDecoration(labelText: label, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))));
}

class HomeScreen extends StatefulWidget {
  final MikrotikApi api; final String ip, user, pass;
  const HomeScreen({super.key, required this.api, required this.ip, required this.user, required this.pass});
  @override State<HomeScreen> createState()=>_HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  int selectedPkg = 0;
  int count = 1;
  List<String> generated = [];
  int todayCards = 0, todaySales = 0, expenses = 0;
  int activeCount = 0, usersCount = 0;
  bool busy = false;
  String status = '';
  String printerName = 'لم يتم اختيار طابعة';
  @override void initState(){ super.initState(); _loadStats(); _refreshCounts(); }
  Package get pkg => packages[selectedPkg];

  Future<void> _loadStats() async {
    final p = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0,10);
    if (p.getString('stats_date') != today) { await p.setString('stats_date', today); await p.setInt('today_cards', 0); await p.setInt('today_sales', 0); await p.setInt('expenses', 0); }
    setState((){ todayCards = p.getInt('today_cards') ?? 0; todaySales = p.getInt('today_sales') ?? 0; expenses = p.getInt('expenses') ?? 0; });
  }
  Future<void> _saveStats() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt('today_cards', todayCards); await p.setInt('today_sales', todaySales); await p.setInt('expenses', expenses);
  }
  Future<void> _refreshCounts() async {
    try {
      var a = await widget.api.cmd(['/ip/hotspot/active/print']);
      var u = await widget.api.cmd(['/ip/hotspot/user/print']);
      setState((){ activeCount = a.length; usersCount = u.length; });
    } catch(_){}
  }
  String _rand7(){ final r = Random(); String s=''; while(s.length<7){ s += r.nextInt(10).toString(); } if(s=='0000000') return _rand7(); return s; }

  Future<void> _generate() async {
    setState(()=>busy=true);
    try {
      List<String> newCards = [];
      for(int i=0;i<count;i++){
        String num = _rand7();
        var r = await widget.api.cmd(['/ip/hotspot/user/add', '=name=$num', '=password=$num', '=profile=${pkg.profile}', '=limit-uptime=${pkg.days}d', '=limit-bytes-total=${pkg.quotaGB * 1024 * 1024 * 1024}']);
        if (r.any((m) => m.containsKey('message'))) throw 'الراوتر رفض: ${r.first['message']}';
        newCards.add(num);
      }
      generated = newCards;
      todayCards += newCards.length; todaySales += newCards.length * pkg.price;
      await _saveStats(); await _refreshCounts();
      setState(()=>status='تم توليد ${newCards.length} كارت');
    } catch(e){ setState(()=>status='خطأ: $e'); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    setState(()=>busy=false);
  }

  Future<List<int>> _cardToImageBytes(String cardNum, Package p) async {
    final data = await rootBundle.load('assets/card_template.png');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    final templateImg = frame.image;
    const int w = 576; const int h = 720;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawImageRect(templateImg, Rect.fromLTWH(0,0,templateImg.width.toDouble(), templateImg.height.toDouble()), Rect.fromLTWH(0,0,w.toDouble(), h.toDouble()), Paint());
    canvas.drawRect(Rect.fromLTWH(50, 380, w-100, 160), Paint()..color = Colors.black);
    final tp = TextPainter(text: TextSpan(text: cardNum, style: const TextStyle(fontSize: 110, fontWeight: FontWeight.w900, color: Colors.white)), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout(maxWidth: w-60);
    tp.paint(canvas, Offset((w - tp.width)/2, 400));
    canvas.drawRect(Rect.fromLTWH(70, 580, w-140, 55), Paint()..color = Colors.black);
    final tp2 = TextPainter(text: TextSpan(text: 'Price: ${p.price}  |  Quota: ${p.quotaGB}GB', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)), textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout(maxWidth: w-60);
    tp2.paint(canvas, Offset((w - tp2.width)/2, 592));
    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = bd!.buffer.asUint8List();
    List<int> out = []; out.addAll([0x1B,0x40]); out.addAll([0x1B,0x61,0x01]);
    int bpr = (w+7)~/8;
    out.addAll([0x1D,0x76,0x30,0x00, bpr & 0xFF, (bpr>>8)&0xFF, h & 0xFF, (h>>8)&0xFF]);
    for(int y=0;y<h;y++){ for(int bx=0;bx<bpr;bx++){ int b=0; for(int bit=0;bit<8;bit++){ int x=bx*8+bit; if(x>=w) continue; int idx=(y*w+x)*4; int gray=(rgba[idx]+rgba[idx+1]+rgba[idx+2])~/3; if(gray<150) b |= (0x80>>bit); } out.add(b); } }
    out.addAll(utf8.encode('\n\n\n\n\n\n')); out.addAll([0x1B,0x64,0x05]); out.addAll([0x1D,0x56,0x01]);
    return out;
  }
  Future<void> _pickPrinter() async {
    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths;
      if (devices.isEmpty) throw 'مفيش طابعة متوصلة - اعمل Pair من اعدادات الموبايل الاول';
      if (!mounted) return;
      showDialog(context: context, builder: (_) => AlertDialog(title: const Text('اختر الطابعة'), content: SizedBox(width: double.maxFinite, height: 300, child: ListView(children: devices.map((d) => ListTile(title: Text(d.name), subtitle: Text(d.macAdress), onTap: () async { Navigator.pop(context); final ok = await PrintBluetoothThermal.connect(macPrinterAddress: d.macAdress); setState(() => printerName = ok ? d.name : 'فشل الاتصال'); })).toList())), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('اغلاق'))]));
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  Future<void> _printBluetooth() async {
    if (generated.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ولّد كروت الأول'))); return; }
    setState(() => busy = true);
    try {
      bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) { await _pickPrinter(); connected = await PrintBluetoothThermal.connectionStatus; if (!connected) throw 'اختر الطابعة الاول'; }
      for (final c in generated) { await PrintBluetoothThermal.writeBytes(await _cardToImageBytes(c, pkg)); }
      setState(() => status = 'تمت الطباعة بلوتوث ✅');
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ طباعة: $e'))); }
    setState(() => busy = false);
  }
  Future<void> _printCards() async {
    if(generated.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ولّد كروت الأول'))); return; }
    setState(()=>busy=true);
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fazlaka_cards.prn');
      List<int> all = [];
      for(final c in generated){ all.addAll(await _cardToImageBytes(c, pkg)); }
      await file.writeAsBytes(all);
      await Share.shareXFiles([XFile(file.path)], text: 'Fazlaka Cards - افتح في RawBT واطبع');
    } catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
    setState(()=>busy=false);
  }
  Future<void> _testPrinter() async {
    final dir = await getTemporaryDirectory(); final file = File('${dir.path}/test.prn');
    final bytes = await _cardToImageBytes('1234567', pkg);
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: 'Test Print');
  }
  Future<void> _showList(String title, String cmdPath) async {
    try { var res = await widget.api.cmd([cmdPath]); if(!mounted) return; showDialog(context: context, builder: (_)=>AlertDialog(title: Text(title), content: SizedBox(width: double.maxFinite, height: 400, child: ListView(children: res.map((m)=>ListTile(title: Text(m['name'] ?? m['user'] ?? m.toString()), subtitle: Text(m.toString()))).toList())), actions: [TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('إغلاق'))])); } catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }

  @override Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFFF2F2F2), appBar: AppBar(title: const Text('Fazlaka - الباقة - اختر الباقة'), backgroundColor: Colors.white, foregroundColor: Colors.black, actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshCounts)]), body: SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(children: [
      Row(children: [
        Expanded(child: _statCard('Active', '$activeCount', () => _showList('Active Users', '/ip/hotspot/active/print'))),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Users', '$usersCount', () => _showList('All Users', '/ip/hotspot/user/print'))),
      ]),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('النهاردة', style: TextStyle(fontWeight: FontWeight.bold)), Text('$todayCards كارت - $todaySales جنيه', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF009688)))]),
        const Divider(),
        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
          _acc('مبيعات', '$todaySales'), _acc('مصاريف', '$expenses'), _acc('صافي', '${todaySales - expenses}'),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () async { final p = await SharedPreferences.getInstance(); await p.setInt('today_cards', 0); await p.setInt('today_sales', 0); await p.setInt('expenses', 0); _loadStats(); }, child: const Text('تصفير'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () async { final c = TextEditingController(); final v = await showDialog<String>(context: context, builder: (_)=>AlertDialog(title: const Text('أضف مصروف'), content: TextField(controller: c, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'المبلغ')), actions: [TextButton(onPressed: ()=>Navigator.pop(context, c.text), child: const Text('حفظ'))])); if(v!=null && v.isNotEmpty){ setState(()=>expenses += int.tryParse(v) ?? 0); _saveStats(); } }, child: const Text('+ مصروف'))),
        ]),
      ])),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('الباقة - اختر الباقة', textAlign: TextAlign.right, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...List.generate(packages.length, (i){
          final p = packages[i]; final sel = i == selectedPkg;
          return GestureDetector(onTap: ()=>setState(()=>selectedPkg=i), child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: sel ? const Color(0xFF009688) : const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(14)), child: Row(children: [
            Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked, color: sel ? Colors.white : Colors.grey),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(p.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: sel ? Colors.white : Colors.black)),
              Text('${p.price} جنيه | ${p.quotaGB} جيجا | ${p.days} أيام', style: TextStyle(color: sel ? Colors.white70 : Colors.grey)),
            ]),
          ])));
        }),
      ])),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('توليد كروت', textAlign: TextAlign.right, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('الباقة المختارة: ${pkg.name}', textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF009688), fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(children: [
          const Text('عدد الكروت', style: TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          IconButton(onPressed: ()=>setState(()=>count = (count+1).clamp(1, 100)), icon: const Icon(Icons.add), style: IconButton.styleFrom(backgroundColor: const Color(0xFF009688), foregroundColor: Colors.white)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text('$count', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          IconButton(onPressed: ()=>setState(()=>count = (count-1).clamp(1, 100)), icon: const Icon(Icons.remove), style: IconButton.styleFrom(backgroundColor: Colors.white, side: const BorderSide(color: Color(0xFF009688)))),
        ]),
        const SizedBox(height: 14),
        ElevatedButton(onPressed: busy?null:_generate, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF009688), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), child: busy ? const CircularProgressIndicator(color: Colors.white) : const Text('توليد كروت', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        if(status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status, textAlign: TextAlign.center)),
      ])),
      const SizedBox(height: 12),
      if(generated.isNotEmpty) Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const Text('الكروت المولدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)), child: const Text('جاهز للطباعة', style: TextStyle(color: Colors.green)))]),
        const SizedBox(height: 10),
        ...generated.map((c)=>Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: const Color(0xFF009688)), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.credit_card, color: Color(0xFF009688)), const SizedBox(width: 8), Text(c, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 2))]))),
        const Text('راجع الأرقام اللي فوق قبل الطباعة. لو غلط ولّد تاني.', textAlign: TextAlign.right, style: TextStyle(color: Colors.grey)),
      ])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton(onPressed: _testPrinter, child: const Text('تجربة الطابعة'))),
        const SizedBox(width: 10),
        Expanded(child: OutlinedButton(onPressed: generated.isEmpty?null:_generate, child: const Text('إعادة طباعة'))),
      ]),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _pickPrinter, icon: const Icon(Icons.bluetooth), label: Text('طابعة: $printerName', overflow: TextOverflow.ellipsis)))]),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: ElevatedButton(onPressed: busy?null:_printBluetooth, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))), child: const Text('طباعة بلوتوث مباشر', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: OutlinedButton(onPressed: busy?null:_printCards, child: const Text('مشاركة / RawBT'))),
      const SizedBox(height: 20),
    ]))),
  );
  }
  Widget _statCard(String label, String val, VoidCallback onTap) => GestureDetector(onTap: onTap, child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)), child: Column(children: [Text(label, style: const TextStyle(color: Colors.grey)), Text(val, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))])));
  Widget _acc(String l, String v) => Column(children: [Text(l, style: const TextStyle(color: Colors.grey)), Text(v, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]);
}
