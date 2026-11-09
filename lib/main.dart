
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

void main() { runApp(const FazlakaApp()); }

// الراوتر: 10.10.10.1 - admin / asdf4411 - API 8728
// الطابعة: RazyTech-5890IV - Share -> RawBT - .prn
// الافتراضي: قالب الفنادق - انت اللي بتصمم بعد كده

class Package {
  final String name; final String profile; final int price; final int quotaGB; final int days;
  const Package({required this.name, required this.profile, required this.price, required this.quotaGB, required this.days});
}
const List<Package> packages = [
  Package(name: 'باقة 20 - 2 جيجا - 3 أيام', profile: 'profile_20_2GB', price: 20, quotaGB: 2, days: 3),
  Package(name: 'باقة 50 - 8 جيجا - 7 أيام', profile: 'profile_50_8GB', price: 50, quotaGB: 8, days: 7),
  Package(name: 'باقة 100 - 20 جيجا - 30 يوم', profile: 'profile_100_2GB', price: 100, quotaGB: 20, days: 30),
];

class CardTemplate {
  String name; String logoText; String phones; String subtitle;
  bool showPhones; bool showPrice; bool showQuota; bool showSubtitle;
  int layout; // 4=فنادق افتراضي - 0=كلاسيك - 1=ستريت - 2=مينيمال - 3=جرافيتي بتاعك القديم
  double logoSize; double numberSize; double logoSpacing;
  bool useBlackBarPhones; bool useBlackBoxPrice; bool useBorder; bool useDashedLine;
  bool logoSameAsNumber; bool isDefault;
  CardTemplate({required this.name, this.logoText='FAZLAKA', this.phones='01016620065 - 01141418040', this.subtitle='HOTEL  WiFi', this.showPhones=true, this.showPrice=true, this.showQuota=true, this.showSubtitle=true, this.layout=4, this.logoSize=46, this.numberSize=110, this.logoSpacing=2, this.useBlackBarPhones=false, this.useBlackBoxPrice=true, this.useBorder=true, this.useDashedLine=false, this.logoSameAsNumber=true, this.isDefault=false});
  Map<String,dynamic> toJson()=>{'name':name,'logoText':logoText,'phones':phones,'subtitle':subtitle,'showPhones':showPhones,'showPrice':showPrice,'showQuota':showQuota,'showSubtitle':showSubtitle,'layout':layout,'logoSize':logoSize,'numberSize':numberSize,'logoSpacing':logoSpacing,'useBlackBarPhones':useBlackBarPhones,'useBlackBoxPrice':useBlackBoxPrice,'useBorder':useBorder,'useDashedLine':useDashedLine,'logoSameAsNumber':logoSameAsNumber,'isDefault':isDefault};
  factory CardTemplate.fromJson(Map<String,dynamic> j)=>CardTemplate(name:j['name']??'قالب', logoText:j['logoText']??'FAZLAKA', phones:j['phones']??'', subtitle:j['subtitle']??'HOTEL  WiFi', showPhones:j['showPhones']??true, showPrice:j['showPrice']??true, showQuota:j['showQuota']??true, showSubtitle:j['showSubtitle']??true, layout:j['layout']??4, logoSize:(j['logoSize']??46).toDouble(), numberSize:(j['numberSize']??110).toDouble(), logoSpacing:(j['logoSpacing']??2).toDouble(), useBlackBarPhones:j['useBlackBarPhones']??false, useBlackBoxPrice:j['useBlackBoxPrice']??true, useBorder:j['useBorder']??true, useDashedLine:j['useDashedLine']??false, logoSameAsNumber:j['logoSameAsNumber']??true, isDefault:j['isDefault']??false);
  CardTemplate copy()=>CardTemplate.fromJson(toJson());
}

List<CardTemplate> defaultTemplates(){
  return [
    CardTemplate(name: 'القالب الافتراضي ★', layout: 0, isDefault: true, logoText: 'FAZLAKA', subtitle: '', phones: '01016620065 - 01141418040', logoSize: 48, numberSize: 115, logoSpacing: 2, useBorder: false, useBlackBoxPrice: false, useBlackBarPhones: false, useDashedLine: true, showSubtitle: false, showPhones: true, showPrice: true, showQuota: true),
    CardTemplate(name: 'رايق - فخم هادي', layout: 5, isDefault: false, logoText: 'FAZLAKA', subtitle: '', phones: '01016620065 - 01141418040', logoSize: 32, numberSize: 125, logoSpacing: 10, useBorder: false, useBlackBoxPrice: false, useBlackBarPhones: false, useDashedLine: false, showSubtitle: false),
    CardTemplate(name: 'قالب الفنادق - HOTEL WiFi', layout: 4, isDefault: false, logoText: 'FAZLAKA', subtitle: 'HOTEL  WiFi', phones: '01016620065 - 01141418040', logoSize: 48, numberSize: 110, useBorder: true, useBlackBoxPrice: true, useDashedLine: false, showSubtitle: true),
    CardTemplate(name: 'جرافيتي بتاعك القديم', layout: 3, isDefault: false),
    CardTemplate(name: 'ستريت - شريط اسود', layout: 1, useBlackBarPhones: true, useBlackBoxPrice: true, useDashedLine: false, logoSize: 68, numberSize: 125, showSubtitle: false),
    CardTemplate(name: 'مينيمال - نضيف', layout: 2, useDashedLine: false, useBorder: true, useBlackBoxPrice: false, logoSize: 42, numberSize: 100, logoSpacing: 10, showSubtitle: false),
  ];
}

class FazlakaApp extends StatelessWidget { const FazlakaApp({super.key}); @override Widget build(BuildContext context){ return MaterialApp(debugShowCheckedModeBanner:false, title:'Fazlaka', theme: ThemeData(useMaterial3:true, fontFamily:'sans-serif', colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF009688))), home: const LoginScreen()); } }

class MikrotikApi {
  Socket? _sock;
  Future<void> connect(String host, int port) async { _sock = await Socket.connect(host, port, timeout: const Duration(seconds:5)); }
  void _writeWord(String w){ final b=utf8.encode(w); final len=b.length; if(len<0x80) _sock!.add([len]); else if(len<0x4000) _sock!.add([(len>>8)|0x80, len&0xFF]); else _sock!.add([(len>>16)|0xC0,(len>>8)&0xFF,len&0xFF]); _sock!.add(b); }
  void _writeSentence(List<String> words){ for(final w in words) _writeWord(w); _sock!.add([0]); }
  Future<List<Map<String,String>>> _readSentence() async {
    final completer = Completer<List<Map<String,String>>>(); final List<Map<String,String>> out=[]; Map<String,String> cur={}; List<int> buf=[]; StreamSubscription? sub;
    sub = _sock!.listen((data){ buf.addAll(data); int i=0; while(i<buf.length){ int len=buf[i]; i++; if(len==0){ if(cur.isNotEmpty) out.add(Map.from(cur)); cur={}; continue; } if(len & 0x80 !=0){ if(i>=buf.length) break; len=((len&0x7F)<<8)|buf[i]; i++; } if(i+len>buf.length) break; final word=utf8.decode(buf.sublist(i,i+len), allowMalformed:true); i+=len; if(word=='!done'||word=='!re'||word=='!trap'||word=='!fatal'){ if(word!='!re'){ if(cur.isNotEmpty) out.add(Map.from(cur)); cur={}; } if(word=='!done'){ if(!completer.isCompleted){ completer.complete(out); sub?.cancel(); } } } else if(word.startsWith('=')){ final eq=word.indexOf('=',1); if(eq>0) cur[word.substring(1,eq)]=word.substring(eq+1); } } buf=buf.sublist(i); }, onError:(e){ if(!completer.isCompleted) completer.completeError(e); }, onDone:(){ if(!completer.isCompleted) completer.complete(out); });
    return completer.future.timeout(const Duration(seconds:8), onTimeout:()=>out);
  }
  Future<void> login(String user,String pass) async { _writeSentence(['/login','=name=$user','=password=$pass']); var res=await _readSentence(); String? ret; for(var m in res) if(m.containsKey('ret')) ret=m['ret']; if(ret!=null){ final chal=<int>[]; for(int i=0;i<ret.length;i+=2) chal.add(int.parse(ret.substring(i,i+2),radix:16)); final md=md5.convert([0]+utf8.encode(pass)+chal); _writeSentence(['/login','=name=$user','=response=00${md.toString()}']); await _readSentence(); } }
  Future<List<Map<String,String>>> cmd(List<String> w) async { _writeSentence(w); return _readSentence(); }
  void close(){ try{_sock?.destroy();}catch(_){} }
}

class LoginScreen extends StatefulWidget{ const LoginScreen({super.key}); @override State<LoginScreen> createState()=>_LoginScreenState(); }
class _LoginScreenState extends State<LoginScreen>{
  final _ip=TextEditingController(text:'10.10.10.1'); final _user=TextEditingController(text:'admin'); final _pass=TextEditingController(text:'asdf4411');
  bool _showPass=false,_remember=true,_auto=false,_loading=false;
  @override void initState(){ super.initState(); _load(); }
  Future<void> _load() async { final p=await SharedPreferences.getInstance(); setState((){ _ip.text=p.getString('ip')??'10.10.10.1'; _user.text=p.getString('user')??'admin'; _pass.text=p.getString('pass')??'asdf4411'; _remember=p.getBool('remember')??true; _auto=p.getBool('auto')??false; }); if(_auto) _doLogin(); }
  Future<void> _doLogin() async { setState(()=>_loading=true); try{ final api=MikrotikApi(); await api.connect(_ip.text.trim(),8728); await api.login(_user.text.trim(),_pass.text.trim()); final p=await SharedPreferences.getInstance(); if(_remember){ await p.setString('ip',_ip.text.trim()); await p.setString('user',_user.text.trim()); await p.setString('pass',_pass.text.trim()); } await p.setBool('remember',_remember); await p.setBool('auto',_auto); if(!mounted) return; Navigator.pushReplacement(context, MaterialPageRoute(builder:(_)=>HomeScreen(api:api,ip:_ip.text.trim(),user:_user.text.trim(),pass:_pass.text.trim()))); }catch(e){ if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('فشل الدخول: $e'))); } if(mounted) setState(()=>_loading=false); }
  @override Widget build(BuildContext context){ return Scaffold(backgroundColor: const Color(0xFF0F3D3E), body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Container(padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children:[ const Text('FAZLAKA', textAlign:TextAlign.center, style:TextStyle(fontSize:32,fontWeight:FontWeight.w900,color:Color(0xFF009688))), const SizedBox(height:6), const Text('إدارة هوت سبوت MikroTik', textAlign:TextAlign.center, style:TextStyle(color:Colors.grey)), const SizedBox(height:20), TextField(controller:_ip, textAlign:TextAlign.right, decoration:InputDecoration(labelText:'IP الراوتر', border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)))), const SizedBox(height:12), TextField(controller:_user, textAlign:TextAlign.right, decoration:InputDecoration(labelText:'اسم المستخدم', border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)))), const SizedBox(height:12), TextField(controller:_pass, obscureText:!_showPass, textAlign:TextAlign.right, decoration:InputDecoration(labelText:'كلمة السر', border:OutlineInputBorder(borderRadius:BorderRadius.circular(14)), suffixIcon:IconButton(icon:Icon(_showPass?Icons.visibility_off:Icons.visibility), onPressed:()=>setState(()=>_showPass=!_showPass)))), CheckboxListTile(value:_remember, onChanged:(v)=>setState(()=>_remember=v??true), title:const Text('تذكر البيانات', textDirection:TextDirection.rtl)), CheckboxListTile(value:_auto, onChanged:(v)=>setState(()=>_auto=v??false), title:const Text('دخول تلقائي', textDirection:TextDirection.rtl)), const SizedBox(height:10), ElevatedButton(onPressed:_loading?null:_doLogin, style:ElevatedButton.styleFrom(backgroundColor:const Color(0xFF009688), foregroundColor:Colors.white, padding:const EdgeInsets.symmetric(vertical:14), shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(14))), child:_loading?const CircularProgressIndicator(color:Colors.white):const Text('دخول', style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))), ])))))); }
}

class HomeScreen extends StatefulWidget{ final MikrotikApi api; final String ip,user,pass; const HomeScreen({super.key,required this.api,required this.ip,required this.user,required this.pass}); @override State<HomeScreen> createState()=>_HomeScreenState(); }
class _HomeScreenState extends State<HomeScreen>{
  int selectedPkg=0; int count=1; List<String> generated=[]; int todayCards=0,todaySales=0,expenses=0; int activeCount=0,usersCount=0; bool busy=false; String status='';
  List<CardTemplate> templates=[]; int selectedTemplate=0;
  Package get pkg=>packages[selectedPkg];
  CardTemplate get tmpl=>templates.isEmpty?defaultTemplates()[0]:templates[selectedTemplate.clamp(0,templates.length-1)];
  @override void initState(){ super.initState(); _loadStats(); _loadTemplates(); _refreshCounts(); }
  Future<void> _loadTemplates() async { final p=await SharedPreferences.getInstance(); final raw=p.getString('templates'); if(raw==null){ templates=defaultTemplates(); selectedTemplate=0; await _saveTemplates(); } else { try{ final list=jsonDecode(raw) as List; templates=list.map((e)=>CardTemplate.fromJson(e)).toList(); if(templates.isEmpty) templates=defaultTemplates(); if(!templates.any((e)=>e.isDefault)){ templates.insert(0, defaultTemplates()[0]); } selectedTemplate=p.getInt('selected_template')??0; if(selectedTemplate>=templates.length) selectedTemplate=0; }catch(_){ templates=defaultTemplates(); selectedTemplate=0; } } setState((){}); }
  Future<void> _saveTemplates() async { final p=await SharedPreferences.getInstance(); await p.setString('templates', jsonEncode(templates.map((e)=>e.toJson()).toList())); await p.setInt('selected_template', selectedTemplate); }
  Future<void> _loadStats() async { final p=await SharedPreferences.getInstance(); final today=DateTime.now().toIso8601String().substring(0,10); if(p.getString('stats_date')!=today){ await p.setString('stats_date',today); await p.setInt('today_cards',0); await p.setInt('today_sales',0); await p.setInt('expenses',0); } setState((){ todayCards=p.getInt('today_cards')??0; todaySales=p.getInt('today_sales')??0; expenses=p.getInt('expenses')??0; }); }
  Future<void> _saveStats() async { final p=await SharedPreferences.getInstance(); await p.setInt('today_cards',todayCards); await p.setInt('today_sales',todaySales); await p.setInt('expenses',expenses); }
  Future<void> _refreshCounts() async { try{ var a=await widget.api.cmd(['/ppp/active/print']); var u=await widget.api.cmd(['/ip/hotspot/user/print']); setState((){ activeCount=a.length; usersCount=u.length; }); }catch(_){} }
  String _rand7(){ final r=Random(); String s=''; while(s.length<7) s+=r.nextInt(10).toString(); if(s=='0000000') return _rand7(); return s; }
  Future<void> _generate() async { setState(()=>busy=true); try{ List<String> nc=[]; for(int i=0;i<count;i++){ String num=_rand7(); await widget.api.cmd(['/ip/hotspot/user/add','=name=$num','=password=$num','=profile=${pkg.profile}',' =limit-bytes-total=${pkg.quotaGB*1024*1024*1024}']); nc.add(num); } generated=nc; todayCards+=nc.length; todaySales+=nc.length*pkg.price; await _saveStats(); await _refreshCounts(); setState(()=>status='تم توليد ${nc.length} كارت'); }catch(e){ setState(()=>status='خطأ: $e'); } setState(()=>busy=false); }

  Future<List<int>> _cardToImageBytes(String cardNum, Package p, CardTemplate t) async {
    const int w=576;
    if(t.layout==3){
      try{
        final data=await rootBundle.load('assets/card_template.png');
        final codec=await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame=await codec.getNextFrame(); final img0=frame.image;
        const int h=720; final recorder=ui.PictureRecorder(); final canvas=Canvas(recorder, Rect.fromLTWH(0,0,w.toDouble(),h.toDouble()));
        canvas.drawImageRect(img0, Rect.fromLTWH(0,0,img0.width.toDouble(),img0.height.toDouble()), Rect.fromLTWH(0,0,w.toDouble(),h.toDouble()), Paint());
        canvas.drawRect(Rect.fromLTWH(50,380,w-100,160), Paint()..color=Colors.black);
        final tp=TextPainter(text:TextSpan(text:cardNum, style:const TextStyle(fontSize:110,fontWeight:FontWeight.w900,color:Colors.white)), textDirection:TextDirection.ltr, textAlign:TextAlign.center)..layout(maxWidth:w-60);
        tp.paint(canvas, Offset((w-tp.width)/2,400));
        canvas.drawRect(Rect.fromLTWH(70,580,w-140,55), Paint()..color=Colors.black);
        final tp2=TextPainter(text:TextSpan(text:'Price: ${p.price}  |  Quota: ${p.quotaGB}GB', style:const TextStyle(fontSize:32,fontWeight:FontWeight.bold,color:Colors.white)), textDirection:TextDirection.ltr, textAlign:TextAlign.center)..layout(maxWidth:w-60);
        tp2.paint(canvas, Offset((w-tp2.width)/2,592));
        final pic=recorder.endRecording(); final img=await pic.toImage(w,h); final bd=await img.toByteData(format:ui.ImageByteFormat.rawRgba); final rgba=bd!.buffer.asUint8List();
        return _rgbaToEscPos(rgba,w,h);
      }catch(_){}
    }
    // قالب الفنادق + القوالب اللي انت بتصممها - بتترسم من الكود
    const int h=620; final recorder=ui.PictureRecorder(); final canvas=Canvas(recorder, Rect.fromLTWH(0,0,w.toDouble(),h.toDouble()));
    canvas.drawRect(Rect.fromLTWH(0,0,w.toDouble(),h.toDouble()), Paint()..color=Colors.white);
    void drawCenter(String text,double y,double size,FontWeight weight,Color color,double spacing){
      final tp=TextPainter(text:TextSpan(text:text, style:TextStyle(fontSize:size,fontWeight:weight,color:color,letterSpacing:spacing,fontFamily:'sans-serif')), textDirection:TextDirection.ltr, textAlign:TextAlign.center)..layout(maxWidth:w-40);
      tp.paint(canvas, Offset((w-tp.width)/2,y));
    }
    // قالب رايق - هادي وفخم
    if(t.layout==5){
      const int hh=620; final rec2=ui.PictureRecorder(); final cv=Canvas(rec2, Rect.fromLTWH(0,0,w.toDouble(),hh.toDouble()));
      cv.drawRect(Rect.fromLTWH(0,0,w.toDouble(),hh.toDouble()), Paint()..color=Colors.white);
      void dc(String text,double y,double size,FontWeight weight,Color color,double spacing){
        final tp=TextPainter(text:TextSpan(text:text, style:TextStyle(fontSize:size,fontWeight:weight,color:color,letterSpacing:spacing,fontFamily:'serif')), textDirection:TextDirection.ltr, textAlign:TextAlign.center)..layout(maxWidth:w-60);
        tp.paint(cv, Offset((w-tp.width)/2,y));
      }
      dc(t.logoText, 45, 28, FontWeight.w300, Colors.black, 10);
      cv.drawLine(const Offset(70,105), const Offset(506,105), Paint()..color=Colors.black..strokeWidth=1);
      dc(t.phones, 125, 22, FontWeight.w300, Colors.black, 2);
      dc(cardNum, 260, 115, FontWeight.w300, Colors.black, 0);
      String priceText='';
      if(t.showPrice && t.showQuota) priceText='Price: ${p.price}  |  Quota: ${p.quotaGB}GB';
      else if(t.showPrice) priceText='Price: ${p.price}';
      else priceText='Quota: ${p.quotaGB}GB';
      cv.drawLine(const Offset(70,500), const Offset(506,500), Paint()..color=Colors.black..strokeWidth=1);
      dc(priceText, 515, 24, FontWeight.w300, Colors.black, 3);
      cv.drawLine(const Offset(70,555), const Offset(506,555), Paint()..color=Colors.black..strokeWidth=1);
      final pic2=rec2.endRecording(); final img2=await pic2.toImage(w,hh); final bd2=await img2.toByteData(format:ui.ImageByteFormat.rawRgba); return _rgbaToEscPos(bd2!.buffer.asUint8List(),w,hh);
    }
    // برواز مزدوج للفنادق
    if(t.useBorder){ canvas.drawRect(Rect.fromLTWH(18,18,w-36,h-36), Paint()..color=Colors.black..style=PaintingStyle.stroke..strokeWidth=3); canvas.drawRect(Rect.fromLTWH(28,28,w-56,h-56), Paint()..color=Colors.black..style=PaintingStyle.stroke..strokeWidth=1); }
    drawCenter(t.logoText, 32, t.logoSize, FontWeight.w900, Colors.black, t.logoSpacing);
    double y = 32 + t.logoSize + 10;
    if(t.showSubtitle && t.subtitle.trim().isNotEmpty){ drawCenter(t.subtitle, y, 26, FontWeight.bold, Colors.black, 2); y += 42; canvas.drawLine(Offset(60,y), Offset(w-60,y), Paint()..color=Colors.black..strokeWidth=2); y += 18; }
    if(t.showPhones && t.phones.trim().isNotEmpty){
      if(t.useBlackBarPhones){
        canvas.drawRect(Rect.fromLTWH(40, y, w-80, 42), Paint()..color=Colors.black);
        final tp=TextPainter(text:TextSpan(text:t.phones, style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold,color:Colors.white)), textDirection:TextDirection.ltr, textAlign:TextAlign.center)..layout(maxWidth:w-60);
        tp.paint(canvas, Offset((w-tp.width)/2, y+8));
      } else { drawCenter(t.phones, y, 26, FontWeight.bold, Colors.black, 0); }
      y += 62;
    }
    if(t.useDashedLine){
      final pd=Paint()..color=Colors.black..strokeWidth=1.5;
      for(double x=40;x<w-40;x+=14) canvas.drawLine(Offset(x,y), Offset(x+8,y), pd);
      y += 35;
    }
    // للفنادق: رقم الكارت + Welcome تحت
    drawCenter(cardNum, y, t.numberSize, FontWeight.w900, Colors.black, 0);
    y += t.numberSize + 18;
    if(t.layout==4){ drawCenter('Welcome', y, 30, FontWeight.bold, Colors.black, 0); y += 42; }
    if(t.showPrice || t.showQuota){
      String priceText='';
      if(t.showPrice && t.showQuota) priceText='Price: ${p.price}  |  Quota: ${p.quotaGB}GB';
      else if(t.showPrice) priceText='Price: ${p.price}';
      else priceText='Quota: ${p.quotaGB}GB';
      if(t.useBlackBoxPrice){
        canvas.drawRect(Rect.fromLTWH(70, y, w-140, 55), Paint()..color=Colors.black);
        drawCenter(priceText, y+12, 28, FontWeight.bold, Colors.white, 0);
      } else { drawCenter(priceText, y, 30, FontWeight.bold, Colors.black, 0); }
    }
    final pic=recorder.endRecording(); final img=await pic.toImage(w,h); final bd=await img.toByteData(format:ui.ImageByteFormat.rawRgba); final rgba=bd!.buffer.asUint8List();
    return _rgbaToEscPos(rgba,w,h);
  }
  List<int> _rgbaToEscPos(Uint8List rgba,int w,int h){
    List<int> out=[]; out.addAll([0x1B,0x40]); out.addAll([0x1B,0x61,0x01]); int bpr=(w+7)~/8; out.addAll([0x1D,0x76,0x30,0x00, bpr&0xFF,(bpr>>8)&0xFF, h&0xFF,(h>>8)&0xFF]);
    for(int y=0;y<h;y++){ for(int bx=0;bx<bpr;bx++){ int b=0; for(int bit=0;bit<8;bit++){ int x=bx*8+bit; if(x>=w) continue; int idx=(y*w+x)*4; int gray=(rgba[idx]+rgba[idx+1]+rgba[idx+2])~/3; if(gray<150) b|=(0x80>>bit); } out.add(b); } }
    out.addAll(utf8.encode('\n\n\n\n\n\n')); out.addAll([0x1B,0x64,0x05]); out.addAll([0x1D,0x56,0x01]); return out;
  }
  Future<void> _printCards() async { if(generated.isEmpty){ ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('ولّد كروت الأول'))); return; } setState(()=>busy=true); try{ final dir=await getTemporaryDirectory(); final file=File('${dir.path}/fazlaka_cards.prn'); List<int> all=[]; for(final c in generated) all.addAll(await _cardToImageBytes(c,pkg,tmpl)); await file.writeAsBytes(all); await Share.shareXFiles([XFile(file.path)], text:'Fazlaka Cards - افتح في RawBT واطبع'); }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); } setState(()=>busy=false); }
  Future<void> _testPrinter() async { final dir=await getTemporaryDirectory(); final file=File('${dir.path}/test.prn'); final bytes=await _cardToImageBytes('1234567',pkg,tmpl); await file.writeAsBytes(bytes); await Share.shareXFiles([XFile(file.path)], text:'Test Print'); }
  Future<void> _showList(String title,String cmdPath) async { try{ var res=await widget.api.cmd([cmdPath]); if(!mounted) return; showDialog(context:context, builder:(_)=>AlertDialog(title:Text(title), content:SizedBox(width:double.maxFinite,height:400, child:ListView(children: res.map((m)=>ListTile(title:Text(m['name']??m['user']??m.toString()), subtitle:Text(m.toString()))).toList())), actions:[TextButton(onPressed:()=>Navigator.pop(context), child:const Text('إغلاق'))])); }catch(e){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('$e'))); } }

  @override Widget build(BuildContext context){
    return Scaffold(backgroundColor: const Color(0xFFF2F2F2), appBar: AppBar(title: const Text('Fazlaka'), backgroundColor: Colors.white, foregroundColor: Colors.black, actions:[IconButton(icon:const Icon(Icons.style), tooltip:'القوالب', onPressed:() async { await Navigator.push(context, MaterialPageRoute(builder:(_)=>TemplatesScreen(templates: templates, selected: selectedTemplate, onChanged:(list,sel) async { setState((){ templates=list; selectedTemplate=sel; }); await _saveTemplates(); }))); setState((){}); }), IconButton(icon:const Icon(Icons.refresh), onPressed:_refreshCounts)]), body: SingleChildScrollView(padding: const EdgeInsets.all(14), child: Column(children:[
      Row(children:[ Expanded(child:_statCard('Active','$activeCount',()=>_showList('Active Users','/ppp/active/print'))), const SizedBox(width:10), Expanded(child:_statCard('Users','$usersCount',()=>_showList('All Users','/ip/hotspot/user/print'))), ]),
      const SizedBox(height:12),
      Container(padding:const EdgeInsets.all(16), decoration:BoxDecoration(color:Colors.white, borderRadius:BorderRadius.circular(18)), child:Column(children:[ Row(mainAxisAlignment:MainAxisAlignment.spaceBetween, children:[ const Text('النهاردة', style:TextStyle(fontWeight:FontWeight.bold)), Text('$todayCards كارت - $todaySales جنيه', style:const TextStyle(fontWeight:FontWeight.bold,color:Color(0xFF009688)))]), const Divider(), Row(mainAxisAlignment:MainAxisAlignment.spaceAround, children:[ _acc('مبيعات','$todaySales'), _acc('مصاريف','$expenses'), _acc('صافي','${todaySales-expenses}') ]), const SizedBox(height:8), Row(children:[ Expanded(child:OutlinedButton(onPressed:() async { final p=await SharedPreferences.getInstance(); await p.setInt('today_cards',0); await p.setInt('today_sales',0); await p.setInt('expenses',0); _loadStats(); }, child:const Text('تصفير'))), const SizedBox(width:8), Expanded(child:OutlinedButton(onPressed:() async { final c=TextEditingController(); final v=await showDialog<String>(context:context, builder:(_)=>AlertDialog(title:const Text('أضف مصروف'), content:TextField(controller:c, keyboardType:TextInputType.number, decoration:const InputDecoration(hintText:'المبلغ')), actions:[TextButton(onPressed:()=>Navigator.pop(context,c.text), child:const Text('حفظ'))])); if(v!=null&&v.isNotEmpty){ setState(()=>expenses+=int.tryParse(v)??0); _saveStats(); } }, child:const Text('+ مصروف'))), ]), ])),
      const SizedBox(height:12),
      Container(padding:const EdgeInsets.all(16), decoration:BoxDecoration(color:Colors.white, borderRadius:BorderRadius.circular(18)), child:Column(crossAxisAlignment:CrossAxisAlignment.stretch, children:[ const Text('الباقة - اختر الباقة', textAlign:TextAlign.right, style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)), const SizedBox(height:12), ...List.generate(packages.length,(i){ final p=packages[i]; final sel=i==selectedPkg; return GestureDetector(onTap:()=>setState(()=>selectedPkg=i), child:Container(margin:const EdgeInsets.only(bottom:10), padding:const EdgeInsets.all(14), decoration:BoxDecoration(color:sel?const Color(0xFF009688):const Color(0xFFF5F5F5), borderRadius:BorderRadius.circular(14)), child:Row(children:[ Icon(sel?Icons.check_circle:Icons.radio_button_unchecked, color:sel?Colors.white:Colors.grey), const Spacer(), Column(crossAxisAlignment:CrossAxisAlignment.end, children:[ Text(p.name, style:TextStyle(fontSize:17,fontWeight:FontWeight.bold,color:sel?Colors.white:Colors.black)), Text('${p.price} جنيه | ${p.quotaGB} جيجا | ${p.days} أيام', style:TextStyle(color:sel?Colors.white70:Colors.grey)), ]), ]))); }), ])),
      const SizedBox(height:12),
      Container(padding:const EdgeInsets.all(16), decoration:BoxDecoration(color:Colors.white, borderRadius:BorderRadius.circular(18)), child:Column(crossAxisAlignment:CrossAxisAlignment.stretch, children:[ Row(children:[ const Expanded(child:Text('القالب - اختر شكل الكارت', style:TextStyle(fontSize:17,fontWeight:FontWeight.bold))), TextButton(onPressed:() async { await Navigator.push(context, MaterialPageRoute(builder:(_)=>TemplatesScreen(templates:templates, selected:selectedTemplate, onChanged:(list,sel) async { setState((){ templates=list; selectedTemplate=sel; }); await _saveTemplates(); }))); setState((){}); }, child:const Text('صمم قالب +')) ]), const SizedBox(height:8), if(templates.isNotEmpty) Wrap(spacing:8, runSpacing:8, children: List.generate(templates.length,(i){ final sel=i==selectedTemplate; return ChoiceChip(label:Text(templates[i].name + (templates[i].isDefault ? ' ★' : '')), selected:sel, onSelected:(_){ setState(()=>selectedTemplate=i); _saveTemplates(); }); })), const SizedBox(height:6), Text('القالب المختار: ${tmpl.name}', style:const TextStyle(color:Color(0xFF009688), fontWeight:FontWeight.bold)), ])),
      const SizedBox(height:12),
      Container(padding:const EdgeInsets.all(16), decoration:BoxDecoration(color:Colors.white, borderRadius:BorderRadius.circular(18)), child:Column(crossAxisAlignment:CrossAxisAlignment.stretch, children:[ const Text('توليد كروت', textAlign:TextAlign.right, style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)), const SizedBox(height:8), Text('الباقة المختارة: ${pkg.name}  |  القالب: ${tmpl.name}', textAlign:TextAlign.right, style:const TextStyle(color:Color(0xFF009688), fontWeight:FontWeight.bold)), const SizedBox(height:12), Row(children:[ const Text('عدد الكروت', style:TextStyle(fontWeight:FontWeight.bold)), const Spacer(), IconButton(onPressed:()=>setState(()=>count=(count+1).clamp(1,100)), icon:const Icon(Icons.add), style:IconButton.styleFrom(backgroundColor:const Color(0xFF009688), foregroundColor:Colors.white)), Padding(padding:const EdgeInsets.symmetric(horizontal:14), child:Text('$count', style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold))), IconButton(onPressed:()=>setState(()=>count=(count-1).clamp(1,100)), icon:const Icon(Icons.remove), style:IconButton.styleFrom(backgroundColor:Colors.white, side:const BorderSide(color:Color(0xFF009688)))), ]), const SizedBox(height:14), ElevatedButton(onPressed:busy?null:_generate, style:ElevatedButton.styleFrom(backgroundColor:const Color(0xFF009688), foregroundColor:Colors.white, padding:const EdgeInsets.symmetric(vertical:14), shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(30))), child:busy?const CircularProgressIndicator(color:Colors.white):const Text('توليد كروت', style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))), if(status.isNotEmpty) Padding(padding:const EdgeInsets.only(top:8), child:Text(status, textAlign:TextAlign.center)), ])),
      const SizedBox(height:12),
      if(generated.isNotEmpty) Container(padding:const EdgeInsets.all(16), decoration:BoxDecoration(color:Colors.white, borderRadius:BorderRadius.circular(18)), child:Column(crossAxisAlignment:CrossAxisAlignment.stretch, children:[ Row(children:[ const Text('الكروت المولدة', style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)), const Spacer(), Container(padding:const EdgeInsets.symmetric(horizontal:10,vertical:4), decoration:BoxDecoration(color:Colors.green.shade50, borderRadius:BorderRadius.circular(20)), child:const Text('جاهز للطباعة', style:TextStyle(color:Colors.green)))]), const SizedBox(height:10), ...generated.map((c)=>Container(margin:const EdgeInsets.only(bottom:8), padding:const EdgeInsets.all(12), decoration:BoxDecoration(border:Border.all(color:const Color(0xFF009688)), borderRadius:BorderRadius.circular(12)), child:Row(children:[ const Icon(Icons.credit_card, color:Color(0xFF009688)), const SizedBox(width:8), Text(c, style:const TextStyle(fontSize:20,fontWeight:FontWeight.w900,letterSpacing:2))]))), const Text('راجع الأرقام اللي فوق قبل الطباعة. لو غلط ولّد تاني.', textAlign:TextAlign.right, style:TextStyle(color:Colors.grey)), ])),
      const SizedBox(height:12),
      Row(children:[ Expanded(child:OutlinedButton(onPressed:_testPrinter, child:const Text('تجربة الطابعة'))), const SizedBox(width:10), Expanded(child:OutlinedButton(onPressed:generated.isEmpty?null:_generate, child:const Text('إعادة طباعة'))), ]),
      const SizedBox(height:12),
      SizedBox(width:double.infinity, child:ElevatedButton(onPressed:busy?null:_printCards, style:ElevatedButton.styleFrom(backgroundColor:Colors.orange, foregroundColor:Colors.white, padding:const EdgeInsets.symmetric(vertical:16), shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(30))), child:const Text('طباعة - RazyTech', style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)))),
      const SizedBox(height:20),
    ]))));
  }
  Widget _statCard(String l,String v,VoidCallback t)=>GestureDetector(onTap:t, child:Container(padding:const EdgeInsets.all(14), decoration:BoxDecoration(color:Colors.white, borderRadius:BorderRadius.circular(16)), child:Column(children:[Text(l, style:const TextStyle(color:Colors.grey)), Text(v, style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold))])));
  Widget _acc(String l,String v)=>Column(children:[Text(l, style:const TextStyle(color:Colors.grey)), Text(v, style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16))]);
}

class TemplatesScreen extends StatefulWidget{ final List<CardTemplate> templates; final int selected; final Function(List<CardTemplate>,int) onChanged; const TemplatesScreen({super.key, required this.templates, required this.selected, required this.onChanged}); @override State<TemplatesScreen> createState()=>_TemplatesScreenState(); }
class _TemplatesScreenState extends State<TemplatesScreen>{
  late List<CardTemplate> list; late int sel;
  @override void initState(){ super.initState(); list=widget.templates.map((e)=>e.copy()).toList(); sel=widget.selected; }
  void _save(){ widget.onChanged(list,sel); Navigator.pop(context); }
  @override Widget build(BuildContext context){
    return Scaffold(appBar: AppBar(title: const Text('القوالب - صمم بنفسك')), body: ListView(padding: const EdgeInsets.all(14), children:[
      const Text('قالب الفنادق هو الافتراضي ★. صمم قالبك انت، واختار اي واحد للطباعة.', style:TextStyle(color:Colors.grey)),
      const SizedBox(height:12),
      ...List.generate(list.length,(i){
        final t=list[i]; final isSel=i==sel;
        return Container(margin:const EdgeInsets.only(bottom:12), decoration:BoxDecoration(color:Colors.white, border:Border.all(color:isSel?const Color(0xFF009688):Colors.grey.shade300, width:isSel?2:1), borderRadius:BorderRadius.circular(16)), child:Column(children:[
          Container(height:200, width:double.infinity, decoration:const BoxDecoration(color:Colors.white, borderRadius:BorderRadius.only(topLeft:Radius.circular(16), topRight:Radius.circular(16))), child: CustomPaint(painter: _PreviewPainter(t, '5849990', packages[0]), size: const Size(360,200))),
          ListTile(title:Text(t.name + (t.isDefault ? ' ★ الافتراضي' : ''), style:const TextStyle(fontWeight:FontWeight.bold)), subtitle:Text('${t.logoText} | ${t.subtitle} | ${t.phones}'), trailing: Row(mainAxisSize:MainAxisSize.min, children:[ IconButton(icon:const Icon(Icons.check_circle, color:Color(0xFF009688)), onPressed:isSel?null:(){ setState(()=>sel=i); _save(); }), IconButton(icon:const Icon(Icons.edit), onPressed:() async { final edited=await Navigator.push<CardTemplate>(context, MaterialPageRoute(builder:(_)=>TemplateEditor(template:t.copy()))); if(edited!=null){ setState(()=>list[i]=edited); } }), if(!t.isDefault) IconButton(icon:const Icon(Icons.delete, color:Colors.red), onPressed:(){ setState(()=>list.removeAt(i)); if(sel>=list.length) sel=0; }), ])),
        ]));
      }),
      const SizedBox(height:10),
      ElevatedButton.icon(onPressed:() async { final created=await Navigator.push<CardTemplate>(context, MaterialPageRoute(builder:(_)=>TemplateEditor(template:CardTemplate(name:'قالب جديد', layout: 4, subtitle: 'HOTEL  WiFi')))); if(created!=null){ setState(()=>list.add(created)); } }, icon:const Icon(Icons.add), label:const Text('صمم قالب جديد +'), style:ElevatedButton.styleFrom(backgroundColor:const Color(0xFF009688), foregroundColor:Colors.white, padding:const EdgeInsets.symmetric(vertical:14))),
      const SizedBox(height:10),
      ElevatedButton(onPressed:_save, style:ElevatedButton.styleFrom(backgroundColor:Colors.orange, foregroundColor:Colors.white, padding:const EdgeInsets.symmetric(vertical:14)), child:const Text('حفظ واختيار')),
    ]));
  }
}
class _PreviewPainter extends CustomPainter{
  final CardTemplate t; final String num; final Package p; _PreviewPainter(this.t,this.num,this.p);
  @override void paint(Canvas canvas, Size size){
    canvas.drawRect(Rect.fromLTWH(0,0,size.width,size.height), Paint()..color=Colors.white);
    void draw(String text,double y,double sz,FontWeight w,Color c,double spacing){
      final tp=TextPainter(text:TextSpan(text:text, style:TextStyle(fontSize:sz,fontWeight:w,color:c,letterSpacing:spacing)), textDirection:TextDirection.ltr, textAlign:TextAlign.center)..layout(maxWidth:size.width-20);
      tp.paint(canvas, Offset((size.width-tp.width)/2,y));
    }
    if(t.layout==3){ draw('FAZLAKA - جرافيتي',20,18,FontWeight.w900,Colors.black,0); draw(num,70,38,FontWeight.w900,Colors.black,0); draw('Price: ${p.price} | Quota: ${p.quotaGB}GB',130,14,FontWeight.bold,Colors.black,0); return; }
    if(t.useBorder){ canvas.drawRect(Rect.fromLTWH(8,8,size.width-16,size.height-16), Paint()..color=Colors.black..style=PaintingStyle.stroke..strokeWidth:2); canvas.drawRect(Rect.fromLTWH(14,14,size.width-28,size.height-28), Paint()..color=Colors.black..style=PaintingStyle.stroke..strokeWidth:1); }
    draw(t.logoText, 12, t.logoSize*0.55, FontWeight.w900, Colors.black, t.logoSpacing);
    double y=12+t.logoSize*0.55+6;
    if(t.showSubtitle && t.subtitle.isNotEmpty){ draw(t.subtitle, y, 13, FontWeight.bold, Colors.black, 2); y+=22; canvas.drawLine(Offset(30,y), Offset(size.width-30,y), Paint()..color=Colors.black..strokeWidth=1.5); y+=10; }
    if(t.showPhones){ if(t.useBlackBarPhones){ canvas.drawRect(Rect.fromLTWH(30,y,size.width-60,22), Paint()..color=Colors.black); draw(t.phones, y+3, 11, FontWeight.bold, Colors.white, 0); } else draw(t.phones, y, 12, FontWeight.bold, Colors.black, 0); y+=32; }
    if(t.useDashedLine){ final pd=Paint()..color=Colors.black..strokeWidth=1; for(double x=20;x<size.width-20;x+=8) canvas.drawLine(Offset(x,y), Offset(x+4,y), pd); y+=14; }
    draw(num, y, t.numberSize*0.55, FontWeight.w900, Colors.black, 0); y+=t.numberSize*0.55+8;
    if(t.layout==4){ draw('Welcome', y, 14, FontWeight.bold, Colors.black, 0); y+=22; }
    String price=''; if(t.showPrice&&t.showQuota) price='Price: ${p.price} | Quota: ${p.quotaGB}GB'; else if(t.showPrice) price='Price: ${p.price}'; else if(t.showQuota) price='Quota: ${p.quotaGB}GB';
    if(price.isNotEmpty){ if(t.useBlackBoxPrice){ canvas.drawRect(Rect.fromLTWH(50,y,size.width-100,26), Paint()..color=Colors.black); draw(price, y+4, 12, FontWeight.bold, Colors.white, 0); } else draw(price, y, 13, FontWeight.bold, Colors.black, 0); }
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>true;
}

class TemplateEditor extends StatefulWidget{ final CardTemplate template; const TemplateEditor({super.key, required this.template}); @override State<TemplateEditor> createState()=>_TemplateEditorState(); }
class _TemplateEditorState extends State<TemplateEditor>{
  late CardTemplate t; late TextEditingController nameC, logoC, phonesC, subtitleC;
  @override void initState(){ super.initState(); t=widget.template.copy(); nameC=TextEditingController(text:t.name); logoC=TextEditingController(text:t.logoText); phonesC=TextEditingController(text:t.phones); subtitleC=TextEditingController(text:t.subtitle); }
  @override Widget build(BuildContext context){
    return Scaffold(appBar:AppBar(title:const Text('صمم قالبك')), body:SingleChildScrollView(padding:const EdgeInsets.all(16), child:Column(crossAxisAlignment:CrossAxisAlignment.stretch, children:[
      Container(height:240, decoration:BoxDecoration(color:Colors.white, border:Border.all(color:Colors.grey.shade300), borderRadius:BorderRadius.circular(16)), child: CustomPaint(painter:_PreviewPainter(t,'5849990',packages[0]), size:const Size(360,240))),
      const SizedBox(height:6), const Text('معاينة حية - أي تغيير بيبان هنا على طول', textAlign:TextAlign.center, style:TextStyle(color:Colors.grey)),
      const SizedBox(height:16),
      TextField(controller:nameC, onChanged:(v)=>setState(()=>t.name=v), decoration:const InputDecoration(labelText:'اسم القالب - مثلا: قالب الفندق بتاعي', border:OutlineInputBorder())),
      const SizedBox(height:12),
      TextField(controller:logoC, onChanged:(v)=>setState(()=>t.logoText=v), decoration:const InputDecoration(labelText:'نص اللوجو - FAZLAKA', border:OutlineInputBorder())),
      const SizedBox(height:12),
      TextField(controller:subtitleC, onChanged:(v)=>setState(()=>t.subtitle=v), decoration:const InputDecoration(labelText:'السطر تحت اللوجو - HOTEL WiFi', border:OutlineInputBorder())),
      const SizedBox(height:12),
      TextField(controller:phonesC, onChanged:(v)=>setState(()=>t.phones=v), decoration:const InputDecoration(labelText:'أرقام التليفون - سطر واحد', hintText:'01016620065 - 01141418040', border:OutlineInputBorder())),
      const SizedBox(height:12),
      const Text('شكل القالب', style:TextStyle(fontWeight:FontWeight.bold)),
      Wrap(spacing:8, children:[
        ChoiceChip(label:const Text('فنادق ★'), selected:t.layout==4, onSelected:(_)=>setState(()=>{t.layout=4; t.useBorder=true; t.useBlackBoxPrice=true; t.showSubtitle=true; t.useDashedLine=false;})),
        ChoiceChip(label:const Text('كلاسيك'), selected:t.layout==0, onSelected:(_)=>setState(()=>t.layout=0)),
        ChoiceChip(label:const Text('ستريت'), selected:t.layout==1, onSelected:(_)=>setState(()=>{t.layout=1; t.useBlackBarPhones=true; t.useBlackBoxPrice=true; t.useDashedLine=false;})),
        ChoiceChip(label:const Text('مينيمال'), selected:t.layout==2, onSelected:(_)=>setState(()=>{t.layout=2; t.useBorder=true; t.useDashedLine=false;})),
        ChoiceChip(label:const Text('رايق - فخم'), selected:t.layout==5, onSelected:(_)=>setState(()=>{t.layout=5; t.useBorder=false; t.useBlackBoxPrice=false; t.useDashedLine=false; t.showSubtitle=false; t.logoSpacing=10;})),
        ChoiceChip(label:const Text('جرافيتي'), selected:t.layout==3, onSelected:(_)=>setState(()=>t.layout=3)),
      ]),
      const SizedBox(height:12),
      SwitchListTile(value:t.showSubtitle, onChanged:(v)=>setState(()=>t.showSubtitle=v), title:const Text('إظهار سطر الفندق - HOTEL WiFi')),
      SwitchListTile(value:t.showPhones, onChanged:(v)=>setState(()=>t.showPhones=v), title:const Text('إظهار التليفونات')),
      SwitchListTile(value:t.showPrice, onChanged:(v)=>setState(()=>t.showPrice=v), title:const Text('إظهار السعر')),
      SwitchListTile(value:t.showQuota, onChanged:(v)=>setState(()=>t.showQuota=v), title:const Text('إظهار الباقة / الجيجا')),
      SwitchListTile(value:t.useBlackBarPhones, onChanged:(v)=>setState(()=>t.useBlackBarPhones=v), title:const Text('شريط أسود للتليفونات')),
      SwitchListTile(value:t.useBlackBoxPrice, onChanged:(v)=>setState(()=>t.useBlackBoxPrice=v), title:const Text('بوكس أسود للسعر')),
      SwitchListTile(value:t.useBorder, onChanged:(v)=>setState(()=>t.useBorder=v), title:const Text('برواز مزدوج - للفنادق')),
      SwitchListTile(value:t.useDashedLine, onChanged:(v)=>setState(()=>t.useDashedLine=v), title:const Text('خط متقطع')),
      SwitchListTile(value:t.logoSameAsNumber, onChanged:(v)=>setState(()=>t.logoSameAsNumber=v), title:const Text('اللوجو بنفس خط الأرقام')),
      const SizedBox(height:12),
      Text('حجم اللوجو: ${t.logoSize.toInt()}'),
      Slider(value:t.logoSize, min:24, max:80, onChanged:(v)=>setState(()=>t.logoSize=v)),
      Text('حجم رقم الكارت: ${t.numberSize.toInt()}'),
      Slider(value:t.numberSize, min:70, max:140, onChanged:(v)=>setState(()=>t.numberSize=v)),
      Text('تباعد حروف اللوجو: ${t.logoSpacing.toInt()}'),
      Slider(value:t.logoSpacing, min:0, max:12, onChanged:(v)=>setState(()=>t.logoSpacing=v)),
      const SizedBox(height:16),
      ElevatedButton(onPressed:(){ t.name=nameC.text.trim().isEmpty?'قالب':nameC.text.trim(); t.logoText=logoC.text.trim().isEmpty?'FAZLAKA':logoC.text.trim(); t.phones=phonesC.text.trim(); t.subtitle=subtitleC.text.trim(); Navigator.pop(context,t); }, style:ElevatedButton.styleFrom(backgroundColor:const Color(0xFF009688), foregroundColor:Colors.white, padding:const EdgeInsets.symmetric(vertical:14)), child:const Text('حفظ القالب')),
    ])));
  }
}
