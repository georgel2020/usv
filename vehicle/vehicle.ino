#include <Arduino.h>

#ifdef BLUETOOTH
#include <BLEDevice.h>
#endif

#ifdef WIFI
#include <WiFi.h>
#include <WiFiUdp.h>
#endif

#ifdef BLUETOOTH
#define CONTROL_SERVICE_UUID "1eba326c-dfb5-4107-b052-97e6e8ffec90"
#define L_PROP_CHARACTERISTIC_UUID "a4d40b3b-3a0a-403a-8eb5-eae4ce620bd4"
#define R_PROP_CHARACTERISTIC_UUID "dbe2a780-0658-4bec-a2e3-fa0581b36d20"
#endif

#ifdef WIFI
#define WIFI_SSID "Untitled_USV"
#define WIFI_PASSWORD "Untitled_USV"
#define LOCAL_PORT 4210
#endif

#define LED_BLUE 2
#define L_PROP 25
#define R_PROP 26

#define PROP_SIGNAL_MAX 102
#define PROP_SIGNAL_MIN 51
#define PROP_SIGNAL_ZERO 77

#ifdef BLUETOOTH
#define MAX_PROP_FACTOR 25
#define L_PROP_FACTOR 25
#define R_PROP_FACTOR 25
#endif

#ifdef WIFI
WiFiUDP Udp;
struct MotorSpeeds {
  int16_t lPropValue;
  int16_t rPropValue;
} __attribute__((packed));
static unsigned long lastWifiDataTime = 0;
#endif

#ifdef BLUETOOTH
class UsvServerCallbacks : public BLEServerCallbacks
{
    void onConnect(BLEServer *pServer)
    {
        digitalWrite(LED_BLUE, HIGH);
    };

    void onDisconnect(BLEServer *pServer)
    {
        ledcWrite(L_PROP, PROP_SIGNAL_ZERO);
        ledcWrite(R_PROP, PROP_SIGNAL_ZERO);
        digitalWrite(LED_BLUE, LOW);
        pServer->startAdvertising();
    }
};
class ControlCallbacks : public BLECharacteristicCallbacks
{
    void onWrite(BLECharacteristic *pCharacteristic)
    {
        bool isLProp = pCharacteristic->getUUID().toString() == L_PROP_CHARACTERISTIC_UUID;

        // Convert the received characteristic value to prop value.
        String strValue = pCharacteristic->getValue();
        size_t length = strValue.length();

        int8_t receivedInt8 = static_cast<int8_t>(strValue.charAt(0));
        long escSignal = map(receivedInt8 * (isLProp ? L_PROP_FACTOR : R_PROP_FACTOR), -5 * MAX_PROP_FACTOR, 5 * MAX_PROP_FACTOR, PROP_SIGNAL_MIN, PROP_SIGNAL_MAX);

        if (isLProp)
        {
            ledcWrite(L_PROP, escSignal);
        }
        else
        {
            ledcWrite(R_PROP, escSignal);
        }
    }
};
#endif

void setup()
{
    // Initialize built-in LED.
    pinMode(LED_BLUE, OUTPUT);

    // Initialize propellers.
    ledcAttach(L_PROP, 50, 10);
    ledcAttach(R_PROP, 50, 10);
    ledcWrite(L_PROP, PROP_SIGNAL_ZERO);
    ledcWrite(R_PROP, PROP_SIGNAL_ZERO);

    // Initialize serial.
    Serial.begin(115200);
    Serial.println("Initialized serial. ");

#ifdef BLUETOOTH
    // Initialize Bluetooth.
    BLEDevice::init("Untitled USV");
    BLEServer *pServer = BLEDevice::createServer();
    BLEService *pControlService = pServer->createService(CONTROL_SERVICE_UUID);
    BLECharacteristic *pLPropCharacteristic = pControlService->createCharacteristic(L_PROP_CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_WRITE);
    BLECharacteristic *pRPropCharacteristic = pControlService->createCharacteristic(R_PROP_CHARACTERISTIC_UUID, BLECharacteristic::PROPERTY_WRITE);
    pLPropCharacteristic->setCallbacks(new ControlCallbacks());
    pRPropCharacteristic->setCallbacks(new ControlCallbacks());
    pControlService->start();
    pServer->setCallbacks(new UsvServerCallbacks);
    BLEDevice::startAdvertising();
#endif

#ifdef WIFI
    // Initialize WiFi.
    WiFi.softAP(WIFI_SSID, WIFI_PASSWORD);
    Udp.begin(LOCAL_PORT);
    IPAddress ip = WiFi.softAPIP();
    Serial.print("AP IP address: ");
    Serial.println(ip);
#endif
}

void loop()
{
#ifdef WIFI
    int packetSize = Udp.parsePacket();
    if (packetSize == sizeof(MotorSpeeds))
    {
        MotorSpeeds receivedSpeeds;
        Udp.read((byte *)&receivedSpeeds, sizeof(MotorSpeeds));

        receivedSpeeds.lPropValue = ntohs(receivedSpeeds.lPropValue);
        receivedSpeeds.rPropValue = ntohs(receivedSpeeds.rPropValue);

        int lPropValue = receivedSpeeds.lPropValue;
        int rPropValue = receivedSpeeds.rPropValue;

        int lPropPwm = map(lPropValue, -100, 100, PROP_SIGNAL_MIN, PROP_SIGNAL_MAX);
        int rPropPwm = map(rPropValue, -100, 100, PROP_SIGNAL_MIN, PROP_SIGNAL_MAX);

        lPropPwm = constrain(lPropPwm, PROP_SIGNAL_MIN, PROP_SIGNAL_MAX);
        rPropPwm = constrain(rPropPwm, PROP_SIGNAL_MIN, PROP_SIGNAL_MAX);

        ledcWrite(L_PROP, lPropPwm);
        ledcWrite(R_PROP, rPropPwm);

        Serial.print("Motor 1 PWM: ");
        Serial.print(lPropPwm);
        Serial.print(", Motor 2 PWM: ");
        Serial.println(rPropPwm);

        lastWifiDataTime = millis();
    }

    // Stop propellers if no data received for 3 seconds.
    if (millis() - lastWifiDataTime > 3000)
    {
        ledcWrite(L_PROP, PROP_SIGNAL_ZERO);
        ledcWrite(R_PROP, PROP_SIGNAL_ZERO);
        Serial.println("No data received for 3 seconds. Stopping propellers. ");
    }

    delay(10);
#endif
}
