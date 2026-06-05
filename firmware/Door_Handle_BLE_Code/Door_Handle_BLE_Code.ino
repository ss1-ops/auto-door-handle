#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <Adafruit_NeoPixel.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ElegantOTA.h>

// ================== PIN DEFINITIONS ==================
const int MOTOR_IN1     = 5;
const int MOTOR_IN2     = 6;
const int MOTOR_ENA     = 7;

const int LIMIT_OPEN    = 8;
const int LIMIT_CLOSED  = 9;

#define RGB_PIN     21
#define NUM_PIXELS  1

Adafruit_NeoPixel pixel(NUM_PIXELS, RGB_PIN, NEO_RGB + NEO_KHZ800);

// ================== WiFi & OTA ==================
const char* ssid = "WAVLINK-N";
const char* password = "Jk12345678";

WebServer server(80);

// ================== BLE DEFINITIONS ==================
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLECharacteristic *pCharacteristic;

// ================== LED HELPERS ==================
void setRed()    { pixel.setPixelColor(0, pixel.Color(255, 0, 0)); pixel.show(); }
void setGreen()  { pixel.setPixelColor(0, pixel.Color(0, 255, 0)); pixel.show(); }
void setYellow() { pixel.setPixelColor(0, pixel.Color(255, 180, 0)); pixel.show(); }

void flashGreen(int times = 1) {
  for (int i = 0; i < times; i++) {
    setGreen(); delay(180); pixel.setPixelColor(0, 0); pixel.show(); delay(180);
  }
}

void flashYellow(int times = 1) {
  for (int i = 0; i < times; i++) {
    setYellow(); delay(200); pixel.setPixelColor(0, 0); pixel.show(); delay(200);
  }
}

void sendStatus(const char* status) {
  if (pCharacteristic) {
    pCharacteristic->setValue(status);
    pCharacteristic->notify();
    Serial.print("Sent status: ");
    Serial.println(status);
  }
}

// ================== MOTOR HELPERS ==================
void motorForward() { digitalWrite(MOTOR_IN1, HIGH); digitalWrite(MOTOR_IN2, LOW);  digitalWrite(MOTOR_ENA, HIGH); }
void motorReverse() { digitalWrite(MOTOR_IN1, LOW);  digitalWrite(MOTOR_IN2, HIGH); digitalWrite(MOTOR_ENA, HIGH); }
void motorStop()    { digitalWrite(MOTOR_IN1, LOW);  digitalWrite(MOTOR_IN2, LOW);  digitalWrite(MOTOR_ENA, LOW); }

// ================== DOOR CYCLE ==================
void runDoorCycle() {
  sendStatus("Opening");
  motorForward();
  unsigned long startTime = millis();
  while (digitalRead(LIMIT_OPEN) == HIGH) {
    flashGreen(1);
    if (millis() - startTime > 10000) break;
  }
  motorStop();

  sendStatus("Open");
  setGreen();
  delay(2000);

  sendStatus("Closing");
  motorReverse();
  startTime = millis();
  while (digitalRead(LIMIT_CLOSED) == HIGH) {
    flashYellow(1);
    if (millis() - startTime > 10000) break;
  }
  motorStop();

  sendStatus("Closed");
  setRed();
  Serial.println("Cycle complete");
}

// ================== BLE CALLBACK ==================
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) {
      String value = pChar->getValue();
      if (value == "OPEN") {
        Serial.println("OPEN received from iPhone");
        runDoorCycle();
      }
    }
};

void setup() {
  Serial.begin(115200);
  delay(1000);

  // Pin setup
  pinMode(MOTOR_IN1, OUTPUT);
  pinMode(MOTOR_IN2, OUTPUT);
  pinMode(MOTOR_ENA, OUTPUT);
  pinMode(LIMIT_OPEN, INPUT_PULLUP);
  pinMode(LIMIT_CLOSED, INPUT_PULLUP);
  motorStop();

  // RGB LED
  pixel.begin();
  pixel.setBrightness(130);
  setRed();

  // ================== WiFi + OTA ==================
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected!");
  Serial.print("IP: http://");
  Serial.println(WiFi.localIP());

  ElegantOTA.begin(&server);
  server.begin();
  Serial.println("OTA ready → http://" + WiFi.localIP().toString() + "/update");

  // ================== BLE Setup ==================
  BLEDevice::init("DoorOpener");

  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_WRITE |
                      BLECharacteristic::PROPERTY_NOTIFY);

  pCharacteristic->setCallbacks(new MyCallbacks());
  pCharacteristic->setValue("Closed");

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  BLEDevice::startAdvertising();

  sendStatus("Closed");

  Serial.println("=== Door Opener Ready (BLE + OTA + Advertising Fix) ===");
}

void loop() {
  server.handleClient();
  ElegantOTA.loop();

  // CRITICAL: Keep BLE advertising alive
  if (!BLEDevice::getAdvertising()->isAdvertising()) {
    Serial.println("Advertising stopped - restarting...");
    BLEDevice::getAdvertising()->start();
  }

  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    if (input == "OPEN") {
      runDoorCycle();
    }
  }
  delay(10);
}