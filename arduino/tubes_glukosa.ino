#include <WiFi.h>
#include <FirebaseESP32.h>
#include <Wire.h>
#include "MAX30105.h"
#include "heartRate.h"
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// --- Konfigurasi ---
#define WIFI_SSID "wizzy"
#define WIFI_PASSWORD "wizzy123"
#define API_KEY "AIzaSyDLv6jwvgqms97G8L0GEee3hF64T7PB1Io"
#define DATABASE_URL "https://tubes-iot-1bb8c-default-rtdb.firebaseio.com/"
#define USER_EMAIL "badawi@gmail.com"
#define USER_PASSWORD "badawi123"

// --- Pinout & Konstanta ---
const int I2C_SDA_PIN = 18;
const int I2C_SCL_PIN = 19;
const int OLED_SDA_PIN = 21;
const int OLED_SCL_PIN = 22;

const int SCREEN_WIDTH = 128;
const int SCREEN_HEIGHT = 64;
const int OLED_RESET = -1;

const long MIN_IR_VALUE = 50000;
const byte PULSE_AMPLITUDE_RED = 0x0A;
const int MIN_BPM = 30;
const int MAX_BPM = 200;

// --- Objek Global ---
FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
TwoWire I2C_Sensor = TwoWire(1);
MAX30105 particleSensor;

unsigned long lastBeat = 0;

// --- Deklarasi Fungsi ---
void initOLED();
void initSensor();
void connectWiFi();
void initFirebase();
void displayMessage(const String &line1, const String &line2 = "", int size1 = 1, int size2 = 1);
void updateOLEDData(float bpm, long redValue, float glucose);
void sendDataToFirebase(float bpm, long irValue, long redValue);
float getGlucoseFromFirebase();

// =================================================================
//                      SETUP
// =================================================================
void setup() {
    Serial.begin(115200);
    Serial.println("Booting...");

    initOLED();
    initSensor();
    connectWiFi();
    initFirebase();

    displayMessage("Siap!", "Letakkan jari...", 2, 1);
}

// =================================================================
//                      LOOP
// =================================================================
void loop() {
    long irValue = particleSensor.getIR();

    if (irValue < MIN_IR_VALUE) {
        return;
    }

    if (checkForBeat(irValue)) {
        unsigned long now = millis();
        float bpm = 60.0 / (now - lastBeat) * 1000.0;
        lastBeat = now;

        if (bpm > MIN_BPM && bpm < MAX_BPM) {
            long redValue = particleSensor.getRed();

            Serial.printf("BPM: %.1f, IR: %ld, Red: %ld\n", bpm, irValue, redValue);

            sendDataToFirebase(bpm, irValue, redValue);
            float glucose = getGlucoseFromFirebase();

            updateOLEDData(bpm, redValue, glucose);
        }
    }
}

// =================================================================
//                FUNGSI-FUNGSI INISIALISASI
// =================================================================

void initOLED() {
    Wire.begin();
    if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
        Serial.println(F("Gagal menginisialisasi SSD1306"));
        while (true);
    }
    displayMessage("Memulai...");
}

void initSensor() {
    I2C_Sensor.begin(I2C_SDA_PIN, I2C_SCL_PIN);
    displayMessage("Inisialisasi Sensor...");

    if (!particleSensor.begin(I2C_Sensor, I2C_SPEED_STANDARD)) {
        Serial.println("MAX30102 tidak terdeteksi pada I2C1");
        displayMessage("Sensor Error", "Periksa koneksi!");
        while (true);
    }
    particleSensor.setup();
    particleSensor.setPulseAmplitudeRed(PULSE_AMPLITUDE_RED);
    particleSensor.setPulseAmplitudeGreen(0);
}

void connectWiFi() {
    displayMessage("Koneksi WiFi...");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    Serial.print("Menghubungkan ke WiFi");
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi Terhubung");
}

void initFirebase() {
    displayMessage("Koneksi Firebase...");
    config.api_key = API_KEY;
    config.database_url = DATABASE_URL;
    auth.user.email = USER_EMAIL;
    auth.user.password = USER_PASSWORD;

    Firebase.begin(&config, &auth);
    Firebase.reconnectWiFi(true);
}

// =================================================================
//                   FUNGSI-FUNGSI HELPER
// =================================================================

void displayMessage(const String &line1, const String &line2, int size1, int size2) {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(0, 0);
    display.setTextSize(size1);
    display.println(line1);
    if (line2.length() > 0) {
        display.setCursor(0, (size1 * 8) + 2);
        display.setTextSize(size2);
        display.println(line2);
    }
    display.display();
}

void updateOLEDData(float bpm, long redValue, float glucose) {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);

    display.setCursor(0, 0);
    display.setTextSize(1);
    display.println("Detak Jantung:");
    display.setTextSize(2);
    display.print(bpm, 1);
    display.println(" BPM");

    display.setCursor(0, 32);
    display.setTextSize(1);
    display.println("Prediksi Glukosa:");
    display.setTextSize(2);
    display.print(glucose, 1);
    display.println(" mg/dL");

    display.display();
}

void sendDataToFirebase(float bpm, long irValue, long redValue) {
    FirebaseJson json;
    float bpmRounded = roundf(bpm * 100) / 100.0;

    json.set("ir", irValue);
    json.set("red", redValue);
    json.set("bpm", bpmRounded);

    if (Firebase.set(fbdo, "/glucose_predict/input", json)) {
        Serial.println("Data terkirim ke Firebase");
    } else {
        Serial.println("Gagal mengirim data: " + fbdo.errorReason());
    }
}

float getGlucoseFromFirebase() {
    if (Firebase.getFloat(fbdo, "/glucose_predict/prediction")) {
        return fbdo.floatData();
    } else {
        Serial.println("Gagal membaca glukosa: " + fbdo.errorReason());
        return -1;
    }
}
