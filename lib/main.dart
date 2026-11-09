import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const FazlakaApp());

// ===== Light Theme - فاتح مش ليلي =====
const lightBg = Color(0xFFEFF3F4);
const cardBg = Color(0xFFFFFFFF);
const innerBg = Color(0xFFF0F4F5);
const turq = Color(0xFF009688);
const turqLight = Color(0xFFE0F2F1);
const darkText = Color(0xFF0A2A33);
const greyText = Color(0xFF607D8B);

class FazlakaApp extends StatelessWidget {
  const FazlakaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(scaffoldBackgroundColor: lightBg),
      home: const Directionality(textDirection: TextDirection.rtl, child: LoginScreen()),
    );
  }
}

class Mikrotik {
  Socket? sock;
  List<int> buf = [];
  Future<void> connect(String ip, String user, String pass) async {
    sock = await Socket.connect(ip, 8728, timeout: const Duration(seconds: 7));
    buf = [];
    sock!.listen((d) { buf.addAll(d); });
    await send(['/login']);
    var res = await readLoop();
    String? retHex;
    for (var s in res) { if (s.containsKey('ret')) retHex = s['ret']; }
    if (retHex == null) throw Exception('الراوتر مردش على طلب الدخول');
    Uint8List chal = Uint8List(retHex.length ~/ 2);
    for (int i = 0; i < chal.length; i++) {
      chal[i] = int.parse(retHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    var m = md5.convert([0, ...utf8.encode(pass), ...chal]).bytes;
    String resp = '00' + m.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await send(['/login', '=name=$user', '=response=$resp']);
    var lr = await readLoop();
    if (lr.any((e) => e.containsKey('!trap'))) throw Exception('اسم المستخدم أو كلمة السر غلط');
  }
  Future<void> send(List<String> words) async {
    for (var w in words) {
      var b = utf8.encode(w);
      if (b.length < 0x80) { sock!.add([b.length]); }
      else if (b.length < 0x4000) { sock!.add([(b.length >> 8) | 0x80, b.length & 0xFF]); }
      else { sock!.add([(b.length >> 16) | 0xC0, (b.length >> 8) & 0xFF, b.length & 0xFF]); }
      sock!.add(b);
    }
    sock!.add([0]);
    await sock!.flush();
  }
  Future<String?> readWord() async {
    for (int t = 0; t < 120; t++) {
      if (buf.isEmpty) { await Future.delayed(const Duration(milliseconds: 50)); continue; }
      int len = buf[0];
      int hLen = 1;
      if (len == 0) { buf.removeAt(0); return ""; }
      if ((len & 0x80) != 0) {
        if ((len & 0xC0) == 0x80) {
          if (buf.length < 2) { await Future.delayed(const Duration(milliseconds: 50)); continue; }
          len = ((len & 0x7F) << 8) + buf[1]; hLen = 2;
        } else {
          if (buf.length < 3) { await Future.delayed(const Duration(milliseconds: 50)); continue; }
          len = ((len & 0x3F) << 16) + (buf[1] << 8) + buf[2]; hLen = 3;
        }
      }
      if (buf.length < hLen + len) { await Future.delayed(const Duration(milliseconds: 50)); continue; }
      var wb = buf.sublist(hLen, hLen + len);
      buf.removeRange(0, hLen + len);
      return utf8.decode(wb);
    }
    return null;
  }
  Future<List<Map<String,String>>> readLoop() async {
    List<Map<String,String>> out = [];
    while (true) {
      List<String> words = [];
      while (true) {
        var w = await readWord();
        if (w == null) return out;
        if (w == "") break;
        words.add(w);
      }
      if (words.isEmpty) continue;
      if (words[0] == '!done') {
        Map<String,String> d = {};
        for (var w in words.skip(1)) {
          if (w.startsWith('=') && w.substring(1).contains('=')) {
            var p = w.substring(1).split('=');
            d[p[0]] = p.sublist(1).join('=');
          }
        }
        if (d.isNotEmpty) out.add(d);
        break;
      }
      if (words[0] == '!trap') { out.add({'!trap': words.join(' ')}); continue; }
      if (words[0] == '!re') {
        Map<String,String> d = {};
        for (var w in words.skip(1)) {
          if (w.startsWith('=') && w.substring(1).contains('=')) {
            var p = w.substring(1).split('=');
            d[p[0]] = p.sublist(1).join('=');
          }
        }
        out.add(d);
      }
    }
    return out;
  }
  Future<List<Map<String,String>>> query(List<String> cmd) async { await send(cmd); return readLoop(); }
  void close() { try { sock?.destroy(); } catch (_) {} }
}

final packages = {
  'باقة 20 - 2 جيجا - 3 أيام': {'profile': 'profile_20_2GB', 'price': '20', 'quota': 2, 'days': 3},
  'باقة 50 - 8 جيجا - 7 أيام': {'profile': 'profile_50_8GB', 'price': '50', 'quota': 8, 'days': 7},
  'باقة 100 - 20 جيجا - 30 يوم': {'profile': 'profile_100_2GB', 'price': '100', 'quota': 20, 'days': 30},
};

Widget fCard({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4))],
    ),
    child: child,
  );
}
Widget cardTitle(IconData icon, String title) {
  return Row(children: [
    Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: turqLight, borderRadius: BorderRadius.circular(9)), child: Icon(icon, color: turq, size: 18)),
    const SizedBox(width: 9),
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: darkText)),
  ]);
}
String formatBytes(String? v) {
  if (v == null || v.isEmpty || v == '0') return 'غير محدود';
  double b = double.tryParse(v) ?? 0;
  if (b == 0) return 'غير محدود';
  if (b >= 1024*1024*1024) return '${(b/(1024*1024*1024)).toStringAsFixed(2)} GB';
  if (b >= 1024*1024) return '${(b/(1024*1024)).toStringAsFixed(1)} MB';
  return '${(b/1024).toStringAsFixed(0)} KB';
}

// ===== LOGIN =====
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState() => _LoginState();
}
class _LoginState extends State<LoginScreen> {
  final ipC = TextEditingController(text: '10.10.10.1');
  final userC = TextEditingController(text: 'admin');
  final passC = TextEditingController();
  bool showPass = false;
  bool remember = true;
  String status = 'غير متصل';
  Color statusColor = Colors.redAccent;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    var p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      ipC.text = p.getString('ip') ?? '10.10.10.1';
      userC.text = p.getString('user') ?? 'admin';
      passC.text = p.getString('pass') ?? '';
    });
  }
  Future<void> _login() async {
    if (passC.text.isEmpty) { setState(() { status = 'اكتب كلمة سر الراوتر الأول!'; statusColor = Colors.redAccent; }); return; }
    setState(() { status = 'جار الاتصال...'; statusColor = Colors.orange; });
    var mk = Mikrotik();
    try {
      await mk.connect(ipC.text.trim(), userC.text.trim(), passC.text);
      if (remember) {
        var p = await SharedPreferences.getInstance();
        await p.setString('ip', ipC.text.trim());
        await p.setString('user', userC.text.trim());
        await p.setString('pass', passC.text);
      }
      var res = await mk.query(['/system/resource/print']);
      var active = await mk.query(['/ip/hotspot/active/print']);
      var users = await mk.query(['/ip/hotspot/user/print']);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: MainScreen(ip: ipC.text.trim(), user: userC.text.trim(), pass: passC.text, routerInfo: res.isNotEmpty ? res[0] : {}, activeCount: active.length, usersCount: users.length))));
    } catch (e) {
      if (mounted) setState(() { status = 'خطأ: $e'; statusColor = Colors.redAccent; });
    } finally {
      mk.close();
    }
  }
  Widget field(String label, TextEditingController c, {bool isPass = false, IconData? icon}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: greyText, fontSize: 13, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: innerBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
        child: TextField(
          controller: c, obscureText: isPass && !showPass, textAlign: TextAlign.right,
          style: const TextStyle(color: darkText, fontSize: 17),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: turq, size: 20),
            suffixIcon: isPass ? IconButton(icon: Icon(showPass ? Icons.visibility_off : Icons.visibility, color: greyText), onPressed: () => setState(() => showPass = !showPass)) : null,
            border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ),
    ]);
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBg,
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: turqLight, borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.wifi, size: 42, color: turq)),
        const SizedBox(height: 14),
        const Text('FAZLAKA', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: turq, letterSpacing: 3)),
        const Text('مدير الهوت سبوت', style: TextStyle(color: greyText, fontSize: 16)),
        const SizedBox(height: 26),
        fCard(child: Column(children: [
          field('عنوان السيرفر', ipC, icon: Icons.dns),
          const SizedBox(height: 16),
          field('اسم المستخدم', userC, icon: Icons.person_outline),
          const SizedBox(height: 16),
          field('كلمة السر', passC, isPass: true, icon: Icons.lock_outline),
        ])),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Checkbox(value: remember, onChanged: (v) => setState(() => remember = v ?? true), activeColor: turq),
          const Text('تذكرني', style: TextStyle(color: darkText, fontSize: 15)),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.circle, size: 8, color: statusColor), const SizedBox(width: 6), Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600))]),
        const SizedBox(height: 18),
        Container(
          width: double.infinity, height: 56,
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00C2A8), Color(0xFF009688)]), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: turq.withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 8))]),
          child: ElevatedButton(onPressed: _login, style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))), child: const Text('اتصال', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1))),
        ),
        const SizedBox(height: 16),
        const Text('RazyTech - 5890IV', style: TextStyle(color: greyText, fontSize: 13)),
      ]))),
    );
  }
}

// ===== MAIN =====
class MainScreen extends StatefulWidget {
  final String ip, user, pass;
  final Map<String,String> routerInfo;
  final int activeCount, usersCount;
  const MainScreen({super.key, required this.ip, required this.user, required this.pass, required this.routerInfo, required this.activeCount, required this.usersCount});
  @override State<MainScreen> createState() => _MainState();
}
class _MainState extends State<MainScreen> {
  String selected = 'باقة 20 - 2 جيجا - 3 أيام';
  int count = 1;
  String result = '';
  List<String> lastCards = [];
  Map<String,dynamic>? lastInfo;
  double totalSales = 0;
  double totalExp = 0;
  int totalCardsSold = 0;
  bool isGenerating = false;
  final expAmountC = TextEditingController();
  final expReasonC = TextEditingController();

  @override void initState() { super.initState(); _loadAccounts(); }
  Future<void> _loadAccounts() async {
    var p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      totalSales = p.getDouble('totalSales') ?? 0;
      totalExp = p.getDouble('totalExp') ?? 0;
      totalCardsSold = p.getInt('totalCardsSold') ?? 0;
      lastCards = p.getStringList('lastCards') ?? [];
      String? pkgName = p.getString('lastPkg');
      if (pkgName != null && packages.containsKey(pkgName)) lastInfo = packages[pkgName];
    });
  }
  Future<void> _saveAccounts() async {
    var p = await SharedPreferences.getInstance();
    await p.setDouble('totalSales', totalSales);
    await p.setDouble('totalExp', totalExp);
    await p.setInt('totalCardsSold', totalCardsSold);
    await p.setStringList('lastCards', lastCards);
    if (lastInfo != null) {
      var found = packages.entries.where((e) => e.value == lastInfo);
      if (found.isNotEmpty) {
        await p.setString('lastPkg', found.first.key);
      }
    }
  }
  Future<void> _resetAccounts() async {
    bool ok = await showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: cardBg, title: const Text('تصفير الحسابات؟', style: TextStyle(color: darkText)), content: const Text('هيمسح المبيعات والمصاريف وعدد الكروت. متأكد؟', style: TextStyle(color: darkText)), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('تصفير', style: TextStyle(color: Colors.redAccent)))])) ?? false;
    if (!ok) return;
    setState(() { totalSales = 0; totalExp = 0; totalCardsSold = 0; lastCards = []; });
    await _saveAccounts();
  }

  Widget smallBox(String title, String value, IconData icon) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: innerBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.shade200)),
      child: Column(children: [
        Icon(icon, color: turq, size: 20),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(color: greyText, fontSize: 12)),
        Text(value, style: const TextStyle(color: darkText, fontSize: 19, fontWeight: FontWeight.bold)),
      ]),
    ));
  }
  Future<void> _generate() async {
    if (isGenerating) return;
    setState(() { isGenerating = true; result = 'جار التوليد...'; });
    var mk = Mikrotik();
    try {
      var pkg = packages[selected]!;
      await mk.connect(widget.ip, widget.user, widget.pass);
      var existing = await mk.query(['/ip/hotspot/user/print']);
      var names = existing.map((e) => e['name'] ?? '').toSet();
      List<String> created = [];
      int tries = 0;
      while (created.length < count && tries < count * 20) {
        tries++;
        var num = (1000000 + Random().nextInt(9000000)).toString();
        if (names.contains(num) || created.contains(num)) continue;
        int limitBytes = (pkg['quota'] as int) * 1024 * 1024 * 1024;
        String limitUptime = '${pkg['days']}d';
        await mk.query(['/ip/hotspot/user/add', '=name=$num', '=profile=${pkg['profile']}', '=server=all', '=limit-bytes-total=$limitBytes', '=limit-uptime=$limitUptime']);
        created.add(num); names.add(num);
      }
      double price = double.tryParse(pkg['price'].toString()) ?? 0;
      if (!mounted) return;
      setState(() { lastCards = created; lastInfo = pkg; totalSales += price * created.length; totalCardsSold += created.length; result = 'تم! ${created.length}/$count كارت - ${pkg['quota']} جيجا - ${pkg['days']} أيام - اتحفظ!'; isGenerating = false; });
      await _saveAccounts();
    } catch (e) {
      if (mounted) setState(() { result = 'خطأ: $e'; isGenerating = false; });
    } finally {
      mk.close();
    }
  }
  Future<void> _print({bool isTest = false}) async {
    try {
      List<int> bytes = [];
      bytes.addAll([0x1B, 0x40]);
      bytes.addAll([0x1B, 0x61, 0x01]);
      if (isTest) {
        bytes.addAll([0x1B, 0x45, 0x01]);
        bytes.addAll([0x1D, 0x21, 0x11]);
        bytes.addAll(utf8.encode('Fazlaka\n'));
        bytes.addAll([0x1D, 0x21, 0x00]);
        bytes.addAll(utf8.encode('RazyTech 5890IV\n'));
        bytes.addAll(utf8.encode('Test OK\n'));
        bytes.addAll([0x1B, 0x45, 0x00]);
        bytes.addAll(utf8.encode('\n\n\n'));
        bytes.addAll([0x1D, 0x56, 0x01]);
      } else {
        if (lastCards.isEmpty) { setState(() => result = 'مفيش كروت! ولد الأول'); return; }
        var pkg = lastInfo!;
        for (var c in lastCards) {
          bytes.addAll([0x1B, 0x40]);
          bytes.addAll([0x1B, 0x61, 0x01]);
          bytes.addAll([0x1B, 0x45, 0x01]);
          bytes.addAll([0x1D, 0x21, 0x11]);
          bytes.addAll(utf8.encode('Fazlaka\n'));
          bytes.addAll([0x1D, 0x21, 0x22]);
          bytes.addAll(utf8.encode('$c\n'));
          bytes.addAll([0x1D, 0x21, 0x00]);
          bytes.addAll([0x1B, 0x45, 0x00]);
          bytes.addAll(utf8.encode('Price: ${pkg['price']}  Quota: ${pkg['quota']}GB\n'));
          bytes.addAll(utf8.encode('Time: ${pkg['days']} Days\n'));
          bytes.addAll(utf8.encode('\n\n\n'));
          bytes.addAll([0x1D, 0x56, 0x01]);
        }
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fazlaka_cards_print.prn');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Print with RawBT');
      if (mounted) setState(() => result = 'اتحفظ - اختار RawBT للطباعة');
    } catch (e) { if (mounted) setState(() => result = 'خطأ طباعة: $e'); }
  }
  @override Widget build(BuildContext context) {
    var pkg = packages[selected]!;
    double net = totalSales - totalExp;
    return Scaffold(
      backgroundColor: lightBg,
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
        Row(children: [
          IconButton(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Directionality(textDirection: TextDirection.rtl, child: LoginScreen()))), icon: const Icon(Icons.menu, color: darkText)),
          const Expanded(child: Text('FAZLAKA', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: turq, letterSpacing: 2))),
          const Icon(Icons.notifications_outlined, color: darkText, size: 26),
        ]),
        const SizedBox(height: 14),
        fCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: cardTitle(Icons.router, 'حالة الراوتر')),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 7, color: Colors.green), SizedBox(width: 5), Text('متصل', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold))])),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Text.rich(TextSpan(children: [const TextSpan(text: 'النشط: ', style: TextStyle(color: greyText)), TextSpan(text: '${widget.activeCount}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: darkText))])),
            const SizedBox(width: 28),
            Text.rich(TextSpan(children: [const TextSpan(text: 'الكروت: ', style: TextStyle(color: greyText)), TextSpan(text: '${widget.usersCount}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: darkText))])),
          ]),
          const SizedBox(height: 8),
          Row(children: [const Icon(Icons.access_time, size: 16, color: greyText), const SizedBox(width: 6), Expanded(child: Text('مدة التشغيل: ${widget.routerInfo['uptime'] ?? '-'}  |  الراوتر: ${widget.routerInfo['board-name'] ?? 'x86'}', style: const TextStyle(color: greyText, fontSize: 13)))]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: ActiveScreen(ip: widget.ip, user: widget.user, pass: widget.pass)))), icon: const Icon(Icons.wifi, size: 18, color: Colors.white), label: const Text('المتصلين الآن', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: turq, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)))),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: UsersScreen(ip: widget.ip, user: widget.user, pass: widget.pass)))), icon: const Icon(Icons.people, size: 18, color: darkText), label: const Text('كل الكروت', style: TextStyle(color: darkText, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade200, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)))),
          ]),
        ])),
        const SizedBox(height: 14),
        fCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          cardTitle(Icons.person_outline, 'الباقة - اختر الباقة'),
          const SizedBox(height: 12),
          ...packages.keys.map((k) {
            bool isSel = k == selected;
            var p = packages[k]!;
            return InkWell(
              onTap: () => setState(() { selected = k; result = 'اخترت: $k'; }),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: isSel ? turq : innerBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: isSel ? turq : Colors.grey.shade300, width: isSel ? 2 : 1),
                  boxShadow: isSel ? [BoxShadow(color: turq.withOpacity(0.3), blurRadius: 12)] : [],
                ),
                child: Row(children: [
                  Icon(isSel ? Icons.radio_button_checked : Icons.radio_button_off, color: isSel ? Colors.white : greyText),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k, style: TextStyle(color: isSel ? Colors.white : darkText, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('${p['price']} جنيه  |  ${p['quota']} جيجا  |  ${p['days']} أيام', style: TextStyle(color: isSel ? Colors.white70 : greyText, fontSize: 13)),
                  ])),
                  if (isSel) const Icon(Icons.check_circle, color: Colors.white, size: 24),
                ]),
              ),
            );
          }).toList(),
        ])),
        const SizedBox(height: 14),
        fCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          cardTitle(Icons.credit_card, 'توليد كروت'),
          const SizedBox(height: 14),
          Row(children: [
            smallBox('السعر', pkg['price'].toString(), Icons.local_offer_outlined),
            const SizedBox(width: 10),
            smallBox('الباقة', '${pkg['quota']} جيجا', Icons.storage_outlined),
            const SizedBox(width: 10),
            smallBox('المدة', '${pkg['days']} أيام', Icons.timer_outlined),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            const Text('عدد الكروت', style: TextStyle(fontSize: 15, color: darkText)),
            const Spacer(),
            InkWell(onTap: () => setState(() { if (count > 1) count--; }), child: Container(width: 42, height: 42, decoration: BoxDecoration(border: Border.all(color: turq), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.remove, color: darkText))),
            const SizedBox(width: 12),
            Text('$count', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: darkText)),
            const SizedBox(width: 12),
            InkWell(onTap: () => setState(() => count++), child: Container(width: 42, height: 42, decoration: BoxDecoration(color: turq, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.add, color: Colors.white))),
          ]),
        ])),
        const SizedBox(height: 16),
        if (result.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(result, textAlign: TextAlign.center, style: const TextStyle(color: turq, fontWeight: FontWeight.bold))),
        if (lastCards.isNotEmpty) fCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: cardTitle(Icons.credit_card, 'الكروت المولدة - ${lastCards.length}')),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)), child: const Text('جاهز للطباعة', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 12),
          ...lastCards.map((c) => Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: innerBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: turq.withOpacity(0.4))),
            child: Row(children: [
              const Icon(Icons.credit_card, color: turq, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(c, textAlign: TextAlign.left, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2, color: darkText))),
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
            ]),
          )).toList(),
          const SizedBox(height: 6),
          const Text('راجع الأرقام اللي فوق قبل الطباعة. لو غلط ولد تاني.', style: TextStyle(color: greyText, fontSize: 12)),
        ])),
        if (lastCards.isNotEmpty) const SizedBox(height: 14),
        Container(width: double.infinity, height: 56, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00C2A8), Color(0xFF009688)]), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: turq.withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 8))]), child: ElevatedButton(onPressed: isGenerating ? null : _generate, style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [if (isGenerating) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) else const Icon(Icons.credit_card, color: Colors.white), const SizedBox(width: 8), Text(isGenerating ? 'جار التوليد...' : 'توليد كروت', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))]))),
        const SizedBox(height: 12),
        Container(width: double.infinity, height: 56, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFA500), Color(0xFFFF6B00)]), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 18, offset: const Offset(0, 8))]), child: ElevatedButton(onPressed: () => _print(), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.print, color: Colors.white), SizedBox(width: 8), Text('طباعة - RazyTech', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))]))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _print(), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 13)), child: const Text('إعادة طباعة', style: TextStyle(color: darkText)))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(onPressed: () => _print(isTest: true), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 13)), child: const Text('تجربة الطابعة', style: TextStyle(color: darkText)))),
        ]),
        const SizedBox(height: 14),
        fCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: cardTitle(Icons.account_balance_wallet_outlined, 'الحسابات')), TextButton(onPressed: _resetAccounts, child: const Text('تصفير', style: TextStyle(color: Colors.redAccent, fontSize: 13)))]),
          const SizedBox(height: 4),
          Text('إجمالي الكروت المباعة: $totalCardsSold', style: const TextStyle(color: greyText, fontSize: 13)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('المبيعات', style: TextStyle(color: greyText, fontSize: 12)), Text('$totalSales جنيه', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green))])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('المصاريف', style: TextStyle(color: greyText, fontSize: 12)), Text('$totalExp جنيه', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent))])),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('الصافي', style: TextStyle(color: greyText, fontSize: 12)), Text('$net جنيه', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: turq))])),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextField(controller: expAmountC, keyboardType: TextInputType.number, style: const TextStyle(color: darkText), decoration: InputDecoration(hintText: 'المبلغ', hintStyle: const TextStyle(color: greyText), filled: true, fillColor: innerBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: expReasonC, style: const TextStyle(color: darkText), decoration: InputDecoration(hintText: 'السبب', hintStyle: const TextStyle(color: greyText), filled: true, fillColor: innerBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 46, child: ElevatedButton(onPressed: () async {
            double v = double.tryParse(expAmountC.text) ?? 0;
            if (v > 0) { setState(() { totalExp += v; expAmountC.clear(); expReasonC.clear(); }); await _saveAccounts(); }
          }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: const Text('إضافة مصروف', style: TextStyle(fontWeight: FontWeight.bold)))),
          const SizedBox(height: 8),
          const Text('الحسابات محفوظة. قفل التطبيق مش هيصفرها.', style: TextStyle(color: greyText, fontSize: 12)),
        ])),
        const SizedBox(height: 20),
      ]))),
    );
  }
}

class ActiveScreen extends StatefulWidget {
  final String ip, user, pass;
  const ActiveScreen({super.key, required this.ip, required this.user, required this.pass});
  @override State<ActiveScreen> createState() => _ActiveState();
}
class _ActiveState extends State<ActiveScreen> {
  List<Map<String,String>> items = [];
  bool loading = true;
  String error = '';
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (mounted) setState(() { loading = true; error = ''; });
    var mk = Mikrotik();
    try {
      await mk.connect(widget.ip, widget.user, widget.pass);
      var res = await mk.query(['/ip/hotspot/active/print']);
      if (mounted) setState(() { items = res; loading = false; });
    } catch (e) { if (mounted) setState(() { loading = false; error = '$e'; }); } finally { mk.close(); }
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBg,
      appBar: AppBar(backgroundColor: lightBg, elevation: 0, title: Text('المتصلين الآن (${items.length})', style: const TextStyle(color: turq, fontWeight: FontWeight.bold)), leading: IconButton(icon: const Icon(Icons.arrow_back, color: darkText), onPressed: () => Navigator.pop(context)), actions: [IconButton(icon: const Icon(Icons.refresh, color: darkText), onPressed: _load)]),
      body: loading ? const Center(child: CircularProgressIndicator(color: turq)) : error.isNotEmpty ? Center(child: Text(error, style: const TextStyle(color: Colors.redAccent))) : items.isEmpty ? const Center(child: Text('مفيش حد متصل دلوقتي', style: TextStyle(color: greyText, fontSize: 18))) : ListView.builder(padding: const EdgeInsets.all(16), itemCount: items.length, itemBuilder: (c, i) {
        var it = items[i];
        return Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.wifi, color: Colors.green, size: 20)), const SizedBox(width: 10), Expanded(child: Text(it['user'] ?? '-', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: darkText))), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10)), child: const Text('متصل', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)))]),
          const SizedBox(height: 10),
          Text('IP: ${it['address'] ?? '-'}  |  MAC: ${it['mac-address'] ?? '-'}', style: const TextStyle(color: greyText)),
          const SizedBox(height: 6),
          Text('مدة الاتصال: ${it['uptime'] ?? '-'}  |  المتبقي: ${it['session-time-left'] ?? '-'}', style: const TextStyle(color: greyText)),
          const SizedBox(height: 6),
          Text('تحميل: ${formatBytes(it['bytes-out'])}  |  رفع: ${formatBytes(it['bytes-in'])}', style: const TextStyle(color: turq, fontWeight: FontWeight.bold)),
        ]));
      }),
    );
  }
}

class UsersScreen extends StatefulWidget {
  final String ip, user, pass;
  const UsersScreen({super.key, required this.ip, required this.user, required this.pass});
  @override State<UsersScreen> createState() => _UsersState();
}
class _UsersState extends State<UsersScreen> {
  List<Map<String,String>> items = [];
  List<Map<String,String>> filtered = [];
  bool loading = true;
  String error = '';
  final searchC = TextEditingController();
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    if (mounted) setState(() { loading = true; error = ''; });
    var mk = Mikrotik();
    try {
      await mk.connect(widget.ip, widget.user, widget.pass);
      var res = await mk.query(['/ip/hotspot/user/print']);
      if (mounted) setState(() { items = res; filtered = res; loading = false; });
    } catch (e) { if (mounted) setState(() { loading = false; error = '$e'; }); } finally { mk.close(); }
  }
  void _search(String q) {
    setState(() { filtered = q.isEmpty ? items : items.where((e) => (e['name'] ?? '').contains(q)).toList(); });
  }
  Future<void> _delete(String id, String name) async {
    bool ok = await showDialog(context: context, builder: (c) => AlertDialog(backgroundColor: cardBg, title: const Text('مسح الكارت؟', style: TextStyle(color: darkText)), content: Text('مسح كارت $name ؟', style: const TextStyle(color: darkText)), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')), TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('مسح', style: TextStyle(color: Colors.redAccent)))])) ?? false;
    if (!ok) return;
    var mk = Mikrotik();
    try {
      await mk.connect(widget.ip, widget.user, widget.pass);
      await mk.query(['/ip/hotspot/user/remove', '=numbers=$id']);
      if (mounted) _load();
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'))); } finally { mk.close(); }
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBg,
      appBar: AppBar(backgroundColor: lightBg, elevation: 0, title: Text('كل الكروت (${filtered.length}/${items.length})', style: const TextStyle(color: turq, fontWeight: FontWeight.bold)), leading: IconButton(icon: const Icon(Icons.arrow_back, color: darkText), onPressed: () => Navigator.pop(context)), actions: [IconButton(icon: const Icon(Icons.refresh, color: darkText), onPressed: _load)]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: TextField(controller: searchC, onChanged: _search, style: const TextStyle(color: darkText), decoration: InputDecoration(hintText: 'بحث برقم الكارت...', hintStyle: const TextStyle(color: greyText), prefixIcon: const Icon(Icons.search, color: turq), filled: true, fillColor: cardBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator(color: turq)) : error.isNotEmpty ? Center(child: Text(error, style: const TextStyle(color: Colors.redAccent))) : filtered.isEmpty ? const Center(child: Text('مفيش كروت', style: TextStyle(color: greyText))) : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: filtered.length, itemBuilder: (c, i) {
          var it = filtered[i];
          bool disabled = it['disabled'] == 'true';
          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)), child: Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: turqLight, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.credit_card, color: turq, size: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it['name'] ?? '-', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkText)),
              const SizedBox(height: 4),
              Text('الباقة: ${it['profile'] ?? '-'}', style: const TextStyle(color: greyText, fontSize: 13)),
              Text('الوقت: ${it['uptime'] ?? '0s'}  |  الحد: ${it['limit-uptime'] ?? '-'}', style: const TextStyle(color: greyText, fontSize: 12)),
              Text('المستهلك: ${formatBytes(it['bytes-total'])} / ${formatBytes(it['limit-bytes-total'])}', style: const TextStyle(color: greyText, fontSize: 12)),
            ])),
            if (disabled) const Text('متوقف', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20), onPressed: () => _delete(it['.id'] ?? '', it['name'] ?? '')),
          ]));
        })),
      ]),
    );
  }
}
