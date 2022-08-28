import 'dart:convert';

import 'package:bs58/bs58.dart';
import 'package:flutter/material.dart';
import 'package:pinenacl/x25519.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'deep_link_provider.dart';

void main() => runApp(const MainApp());

class MainApp extends StatefulWidget {
  const MainApp({Key? key}) : super(key: key);

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final List<Widget> logs = [];
  late PrivateKey sk;
  late PublicKey pk;
  String walletAddr = "";
  String session = "";
  late Box sharedSecret;

  @override
  void initState() {
    super.initState();
    sk = PrivateKey.generate();
    pk = sk.publicKey;
  }

  void _connect() async {
    Uri url = Uri(
      scheme: 'https',
      host: 'phantom.app',
      path: '/ul/v1/connect',
      queryParameters: {
        'dapp_encryption_public_key': base58.encode(pk.asTypedList),
        'cluster': "devnet",
        'app_url': "https://phantom.app",
        'redirect_link': 'flutterphantom://deeplink.connect',
      },
    );
    launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
  }

  _onConnect(Map params) async {
    sharedSecret = Box(
      myPrivateKey: sk,
      theirPublicKey: PublicKey(
        base58.decode(
          params["phantom_encryption_public_key"],
        ),
      ),
    );

    final decryptedData = sharedSecret.decrypt(
      ByteList(base58.decode(
        params["data"],
      )),
      nonce: base58.decode(params["nonce"]),
    );

    Map data = const JsonDecoder().convert(String.fromCharCodes(decryptedData));

    session = data["session"];
    walletAddr = data["public_key"];

    logs.add(
      Text(
        "Wallet address: ${data["public_key"].toString().substring(0, 16)}...",
        style: const TextStyle(
          color: Colors.white,
        ),
      ),
    );
  }

  void _disconnect() async {
    JsonEncoder encoder = const JsonEncoder();
    Map payload = {
      "session": session,
    };
    String payloadJson = encoder.convert(payload);

    final encryptedMsg = sharedSecret.encrypt(
      Uint8List.fromList(payloadJson.codeUnits),
    );

    Uri url = Uri(
      scheme: 'https',
      host: 'phantom.app',
      path: '/ul/v1/disconnect',
      queryParameters: {
        'dapp_encryption_public_key': base58.encode(pk.asTypedList),
        'nonce': base58.encode(encryptedMsg.nonce.toUint8List()),
        'payload': base58.encode(encryptedMsg.toUint8List()),
        'redirect_link': 'flutterphantom://deeplink.disconnect',
      },
    );
    launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    DeepLinkProvider provider = DeepLinkProvider();
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Flutter Phantom Deeplinking"),
        ),
        body: Provider<DeepLinkProvider>(
          create: (context) => provider,
          dispose: (context, provider) => provider.dispose(),
          child: StreamBuilder<String>(
            stream: provider.state,
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                Uri redirectedUri = Uri.parse(snapshot.data!);
                Map params = redirectedUri.queryParameters;
                if (params.containsKey("errorCode")) {
                  print(params["errorMessage"]);
                } else {
                  switch (redirectedUri.host.split('.')[1]) {
                    case 'connect':
                      _onConnect(params);
                      break;
                    case 'disconnect':
                      print('disconnected');
                      break;
                    default:
                  }
                }
              }
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: MediaQuery.of(context).size.width,
                      height: 300,
                      decoration: const BoxDecoration(
                        color: Colors.black,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "LOGS:",
                              style: TextStyle(
                                color: Colors.white,
                              ),
                            ),
                            ...logs,
                          ],
                        ),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: _connect,
                      child: const Text("Connect Phantom"),
                    ),
                    ElevatedButton(
                      onPressed: () => walletAddr == ""
                          ? ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Please connect wallet first",
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            )
                          : _disconnect(),
                      child: const Text("Disconnect"),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
