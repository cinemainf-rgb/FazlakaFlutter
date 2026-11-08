import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const FazlakaApp());

const petrolBg = Color(0xFF0A2A33);
const cardBg = Color(0xFF0F3440);
const innerBg = Color(0xFF0A2A33);
const turq = Color(0xFF00E5D4);

class FazlakaApp extends StatelessWidget {
  const FazlakaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: petrolBg),
      home: const LoginScreen(),
    );
  }
}

// ===== MikroTik API =====
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
    if (retHex == null) return;
    Uint8List chal = Uint8List(retHex.length ~/ 2);
    for (int i = 0; i < chal.length; i++) {
      chal[i] = int.parse(retHex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    var m = md5.convert([0, ...pass.codeUnits, ...chal]).bytes;
    String resp = '00' + m.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await send(['/login', '=name=$user', '=response=$resp']);
    var lr = await readLoop();
    if (lr.any((e) => e.containsKey('!trap'))) throw Exception('Wrong User/Pass');
  }
  Future<void> send(List<String> words) async {
    for (var w in words) {
      var b = w.codeUnits;
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
      return String.fromCharCodes(wb);
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
  'Package 20 - 2GB - 3 Days': {'profile': 'profile_20_2GB', 'price': '20', 'quota': 2, 'days': 3},
  'Package 50 - 8GB - 7 Days': {'profile': 'profile_50_8GB', 'price': '50', 'quota': 8, 'days': 7},
  'Package 100 - 20GB - 30 Days': {'profile': 'profile_100_2GB', 'price': '100', 'quota': 20, 'days': 30},
};

// ===== Card متظبط - مفيش حاجة تطلع بره =====
Widget fCard({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: turq.withOpacity(0.4)),
      boxShadow: [BoxShadow(color: turq.withOpacity(0.10), blurRadius: 16)],
    ),
    child: child,
  );
}
Widget cardTitle(IconData icon, String title) {
  return Row(children: [
    Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: turq.withOpacity(0.15), borderRadius: BorderRadius.circular(9)), child: Icon(icon, color: turq, size: 18)),
    const SizedBox(width: 9),
    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
  ]);
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
  String status = 'Not Connected';
  Color statusColor = Colors.redAccent;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    var p = await SharedPreferences.getInstance();
    ipC.text = p.getString('ip') ?? '10.10.10.1';
    userC.text = p.getString('user') ?? 'admin';
    passC.text = p.getString('pass') ?? '';
  }
  Future<void> _login() async {
    if (passC.text.isEmpty) { setState(() { status = 'Write Router Password First!'; statusColor = Colors.redAccent; }); return; }
    setState(() { status = 'Connecting...'; statusColor = Colors.orange; });
    try {
      var mk = Mikrotik();
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
      mk.close();
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MainScreen(ip: ipC.text.trim(), user: userC.text.trim(), pass: passC.text, routerInfo: res.isNotEmpty ? res[0] : {}, activeCount: active.length, usersCount: users.length)));
    } catch (e) { setState(() { status = 'Error: $e'; statusColor = Colors.redAccent; }); }
  }
  Widget field(String label, TextEditingController c, {bool isPass = false, IconData? icon}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 1)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: innerBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: turq.withOpacity(0.35))),
        child: TextField(
          controller: c, obscureText: isPass && !showPass,
          style: const TextStyle(color: Colors.white, fontSize: 17),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: turq, size: 20),
            suffixIcon: isPass ? IconButton(icon: Icon(showPass ? Icons.visibility_off : Icons.visibility, color: Colors.white54), onPressed: () => setState(() => showPass = !showPass)) : null,
            border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
        ),
      ),
    ]);
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0E3A45), Color(0xFF0A2A33)])),
        child: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(children: [
          const SizedBox(height: 16),
          Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: turq.withOpacity(0.12), borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.wifi, size: 42, color: turq)),
          const SizedBox(height: 14),
          const Text('FAZLAKA', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: turq, letterSpacing: 3)),
          const Text('Hotspot Manager', style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 26),
          fCard(child: Column(children: [
            field('SERVER ADDRESS', ipC, icon: Icons.dns),
            const SizedBox(height: 16),
            field('USERNAME', userC, icon: Icons.person_outline),
            const SizedBox(height: 16),
            field('PASSWORD', passC, isPass: true, icon: Icons.lock_outline),
          ])),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Checkbox(value: remember, onChanged: (v) => setState(() => remember = v ?? true), activeColor: turq, checkColor: Colors.black),
            const Text('Remember Me', style: TextStyle(color: Colors.white, fontSize: 15)),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.circle, size: 8, color: statusColor), const SizedBox(width: 6), Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.w600))]),
          const SizedBox(height: 18),
          Container(
            width: double.infinity, height: 56,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00E5D4), Color(0xFF00B8FF)]), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: turq.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 8))]),
            child: ElevatedButton(onPressed: _login, style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))), child: const Text('CONNECT', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 1))),
          ),
          const SizedBox(height: 16),
          const Text('RazyTech - 5890IV', style: TextStyle(color: Colors.white38, fontSize: 13)),
        ]))),
      ),
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
  String selected = 'Package 20 - 2GB - 3 Days';
  int count = 10;
  String result = '';
  List<String> lastCards = [];
  Map<String,dynamic>? lastInfo;
  double totalSales = 0;
  double totalExp = 0;
  final expAmountC = TextEditingController();
  final expReasonC = TextEditingController();

  Widget smallBox(String title, String value, IconData icon) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: innerBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: turq.withOpacity(0.3))),
      child: Column(children: [
        Icon(icon, color: turq, size: 20),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
      ]),
    ));
  }
  Future<void> _generate() async {
    setState(() => result = 'Generating...');
    try {
      var pkg = packages[selected]!;
      var mk = Mikrotik(); await mk.connect(widget.ip, widget.user, widget.pass);
      var existing = await mk.query(['/ip/hotspot/user/print']);
      var names = existing.map((e) => e['name'] ?? '').toSet();
      List<String> created = [];
      int tries = 0;
      while (created.length < count && tries < count * 20) {
        tries++;
        var num = (1000000 + Random().nextInt(9000000)).toString();
        if (names.contains(num) || created.contains(num)) continue;
        int limitBytes = (pkg['quota'] as int) * 1024 * 1024 * 1024;
        String limitUptime = '${pkg['days']}d 00:00:00';
        await mk.query(['/ip/hotspot/user/add', '=name=$num', '=profile=${pkg['profile']}', '=server=all', '=limit-bytes-total=$limitBytes', '=limit-uptime=$limitUptime']);
        created.add(num); names.add(num);
      }
      mk.close();
      double price = double.tryParse(pkg['price'].toString()) ?? 0;
      setState(() { lastCards = created; lastInfo = pkg; totalSales += price * created.length; result = 'Done! ${created.length}/$count Cards - ${pkg['quota']}GB - ${pkg['days']} Days'; });
    } catch (e) { setState(() => result = 'Error: $e'); }
  }
  Future<void> _print({bool isTest = false}) async {
    try {
      String txt;
      if (isTest) {
        txt = "Fazlaka - Test\nRazyTech 5890IV\nOK\n\n\n";
      } else {
        if (lastCards.isEmpty) { setState(() => result = 'No Cards! Generate First'); return; }
        var pkg = lastInfo!;
        txt = "";
        for (var c in lastCards) { txt += "Fazlaka\n$c\nPrice: ${pkg['price']}  Quota: ${pkg['quota']}GB\n\n\n"; }
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/fazlaka_cards_print.txt');
      await file.writeAsString(txt);
      await Share.shareXFiles([XFile(file.path)], text: 'Print with RawBT');
      setState(() => result = 'Saved - Choose RawBT to Print');
    } catch (e) { setState(() => result = 'Print Error: $e'); }
  }

  @override Widget build(BuildContext context) {
    var pkg = packages[selected]!;
    double net = totalSales - totalExp;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0E3A45), Color(0xFF0A2A33)])),
        child: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(children: [
          Row(children: [
            IconButton(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen())), icon: const Icon(Icons.menu, color: Colors.white)),
            const Expanded(child: Text('FAZLAKA', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: turq, letterSpacing: 2))),
            const Icon(Icons.notifications_outlined, color: Colors.white, size: 26),
          ]),
          const SizedBox(height: 14),
          // Card 1 - Router
          fCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: cardTitle(Icons.router, 'Router Status')),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.4))), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 7, color: Colors.green), SizedBox(width: 5), Text('Online', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold))])),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Text.rich(TextSpan(children: [const TextSpan(text: 'Active: ', style: TextStyle(color: Colors.white54)), TextSpan(text: '${widget.activeCount}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))])),
              const SizedBox(width: 28),
              Text.rich(TextSpan(children: [const TextSpan(text: 'Users: ', style: TextStyle(color: Colors.white54)), TextSpan(text: '${widget.usersCount}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))])),
            ]),
            const SizedBox(height: 8),
            Row(children: [const Icon(Icons.access_time, size: 16, color: Colors.white54), const SizedBox(width: 6), Expanded(child: Text('Uptime: ${widget.routerInfo['uptime'] ?? '-'}  |  Router: ${widget.routerInfo['board-name'] ?? 'x86'}', style: const TextStyle(color: Colors.white70, fontSize: 13)))]),
          ])),
          const SizedBox(height: 14),
          // Card 2 - Profile
          fCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cardTitle(Icons.person_outline, 'Profile'),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12), decoration: BoxDecoration(color: innerBg, borderRadius: BorderRadius.circular(14), border: Border.all(color: turq.withOpacity(0.35))), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: selected, isExpanded: true, dropdownColor: cardBg, icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white), style: const TextStyle(color: Colors.white, fontSize: 15), items: packages.keys.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(), onChanged: (v) => setState(() => selected = v!)))),
          ])),
          const SizedBox(height: 14),
          // Card 3 - Generate
          fCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cardTitle(Icons.credit_card, 'Generate Cards'),
            const SizedBox(height: 14),
            Row(children: [
              smallBox('Price', pkg['price'].toString(), Icons.local_offer_outlined),
              const SizedBox(width: 10),
              smallBox('Quota', '${pkg['quota']}GB', Icons.storage_outlined),
              const SizedBox(width: 10),
              smallBox('Time', '${pkg['days']} Days', Icons.timer_outlined),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              const Text('Number of Cards', style: TextStyle(fontSize: 15)),
              const Spacer(),
              InkWell(onTap: () => setState(() { if (count > 1) count--; }), child: Container(width: 42, height: 42, decoration: BoxDecoration(border: Border.all(color: turq.withOpacity(0.5)), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.remove, color: Colors.white))),
              const SizedBox(width: 12),
              Text('$count', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              InkWell(onTap: () => setState(() => count++), child: Container(width: 42, height: 42, decoration: BoxDecoration(color: turq, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.add, color: Colors.black))),
            ]),
          ])),
          const SizedBox(height: 16),
          if (result.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(result, textAlign: TextAlign.center, style: const TextStyle(color: turq, fontWeight: FontWeight.bold))),
          Container(width: double.infinity, height: 56, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF00E5D4), Color(0xFF00B8FF)]), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: turq.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 8))]), child: ElevatedButton(onPressed: _generate, style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.credit_card, color: Colors.black), SizedBox(width: 8), Text('Generate Cards', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black))]))),
          const SizedBox(height: 12),
          Container(width: double.infinity, height: 56, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFA500), Color(0xFFFF6B00)]), borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 8))]), child: ElevatedButton(onPressed: () => _print(), style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.print, color: Colors.white), SizedBox(width: 8), Text('Print - RazyTech', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white))]))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _print(), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 13)), child: const Text('Reprint', style: TextStyle(color: Colors.white)))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: () => _print(isTest: true), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), padding: const EdgeInsets.symmetric(vertical: 13)), child: const Text('Test Printer', style: TextStyle(color: Colors.white)))),
          ]),
          const SizedBox(height: 14),
          // Card 4 - Accounts - جوه كارت لوحده، مش طالع بره
          fCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cardTitle(Icons.account_balance_wallet_outlined, 'Accounts'),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Sales', style: TextStyle(color: Colors.white54, fontSize: 12)), Text('$totalSales EGP', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green))])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Expenses', style: TextStyle(color: Colors.white54, fontSize: 12)), Text('$totalExp EGP', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.redAccent))])),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Net', style: TextStyle(color: Colors.white54, fontSize: 12)), Text('$net EGP', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: turq))])),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: TextField(controller: expAmountC, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Amount', hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: innerBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: expReasonC, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Reason', hintStyle: const TextStyle(color: Colors.white38), filled: true, fillColor: innerBg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
            ]),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 46, child: ElevatedButton(onPressed: () {
              double v = double.tryParse(expAmountC.text) ?? 0;
              if (v > 0) { setState(() { totalExp += v; expAmountC.clear(); expReasonC.clear(); }); }
            }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.bold)))),
          ])),
          const SizedBox(height: 20),
        ]))),
      ),
    );
  }
}
