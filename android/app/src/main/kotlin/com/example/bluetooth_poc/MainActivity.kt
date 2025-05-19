package com.example.bluetooth_poc

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.ParcelUuid
import android.util.Log
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.*

class MainActivity : FlutterActivity() {
    private val TAG = "BleAdvertiser"

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private var bluetoothAdapter: BluetoothAdapter? = null


    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
            Log.i(TAG, "BLE Advertising started successfully")
        }

        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "BLE Advertising failed: $errorCode")
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val device = result.device
            val rssi = result.rssi

            result.scanRecord?.serviceUuids?.forEach { parcelUuid ->
                val scanResult = mapOf(
                    "deviceId" to device.address,
                    "deviceName" to (device.name ?: "Unknown"),
                    "serviceUuid" to parcelUuid.uuid.toString(),
                    "rssi" to rssi
                )
                eventSink?.success(scanResult)
            }
        }

        override fun onScanFailed(errorCode: Int) {
            Log.e(TAG, "Scan failed: $errorCode")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ble_advertiser")
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "ble_advertiser_scan_results")

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    val uuid = call.argument<String>("serviceUuid") ?: run {
                        result.error("INVALID_ARGUMENT", "serviceUuid is required", null)
                        return@setMethodCallHandler
                    }
                    startAdvertising(uuid)
                    result.success(true)
                }

                "stopAdvertising" -> {
                    stopAdvertising()
                    result.success(true)
                }

                "startScanning" -> {
                    startScanning()
                    result.success(true)
                }

                "stopScanning" -> {
                    stopScanning()
                    result.success(true)
                }

                "isBluetoothEnabled" -> {
                    result.success(bluetoothAdapter?.isEnabled ?: false)
                }

                else -> result.notImplemented()
            }
        }

        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    private fun startAdvertising(uuidStr: String) {
        if (bluetoothAdapter?.isEnabled != true) {
            Log.e(TAG, "Bluetooth not enabled")
            return
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_ADVERTISE) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Missing BLUETOOTH_ADVERTISE permission")
            return
        }

        val parcelUuid = ParcelUuid(UUID.fromString(uuidStr))
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .build()

        val data = AdvertiseData.Builder()
            .addServiceUuid(parcelUuid)
            .setIncludeDeviceName(true)
            .build()

        bluetoothAdapter?.bluetoothLeAdvertiser?.startAdvertising(settings, data, advertiseCallback)
    }

    private fun stopAdvertising() {
        bluetoothAdapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
    }

    private fun startScanning() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_SCAN) != PackageManager.PERMISSION_GRANTED
        ) {
            Log.e(TAG, "Missing BLUETOOTH_SCAN permission")
            return
        }

        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        bluetoothAdapter?.bluetoothLeScanner?.startScan(null, settings, scanCallback)
    }

    private fun stopScanning() {
        bluetoothAdapter?.bluetoothLeScanner?.stopScan(scanCallback)
    }
}
