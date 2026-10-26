import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Con wifi sin salida a internet, conectar al servidor puede colgarse mucho
/// más que los 8 s que esperan las pantallas. Con este límite la falla llega
/// antes, y como es al CONECTAR (el pedido nunca salió), ClienteOffline la
/// puede guardar en la cola sin riesgo de registrarla dos veces.
const tiempoConexion = Duration(seconds: 5);

http.Client crearClienteHttp() => IOClient(HttpClient()..connectionTimeout = tiempoConexion);
