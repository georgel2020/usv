#include <Arduino.h>
#include <BLEDevice.h>

#define CONTROL_SERVICE_UUID "1eba326c-dfb5-4107-b052-97e6e8ffec90"
#define L_PROP_CHARACTERISTIC_UUID "a4d40b3b-3a0a-403a-8eb5-eae4ce620bd4"
#define R_PROP_CHARACTERISTIC_UUID "dbe2a780-0658-4bec-a2e3-fa0581b36d20"

#define LED_BLUE 2
#define L_PROP 25
#define R_PROP 26

#define PROP_SIGNAL_MAX 102
#define PROP_SIGNAL_MIN 51
#define PROP_SIGNAL_ZERO 77

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
        // Convert the received characteristic value to prop value.
        String strValue = pCharacteristic->getValue();
        size_t length = strValue.length();

        int8_t receivedInt8 = static_cast<int8_t>(strValue.charAt(0));
        long escSignal = map(receivedInt8, -5, 5, PROP_SIGNAL_MIN, PROP_SIGNAL_MAX);

        if (pCharacteristic->getUUID().toString() == L_PROP_CHARACTERISTIC_UUID) {
            ledcWrite(L_PROP, escSignal);
        } else {
            ledcWrite(R_PROP, escSignal);
        }
    }
};

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
}

void loop()
{
    
}
