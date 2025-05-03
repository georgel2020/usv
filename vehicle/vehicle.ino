#include <BLEDevice.h>

#define CONTROL_SERVICE_UUID "1eba326c-dfb5-4107-b052-97e6e8ffec90"
#define L_PROP_CHARACTERISTIC_UUID "a4d40b3b-3a0a-403a-8eb5-eae4ce620bd4"
#define R_PROP_CHARACTERISTIC_UUID "dbe2a780-0658-4bec-a2e3-fa0581b36d20"

#define LED_BLUE 2

int _lPropValue = 0;
int _rPropValue = 0;

class UsvServerCallbacks : public BLEServerCallbacks
{
    void onConnect(BLEServer *pServer)
    {
        Serial.println("Device connected. ");
        digitalWrite(LED_BLUE, HIGH);
    };

    void onDisconnect(BLEServer *pServer)
    {
        Serial.println("Device disconnected. ");
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

        if (pCharacteristic->getUUID().toString() == L_PROP_CHARACTERISTIC_UUID) {
            _lPropValue = receivedInt8;
        } else {
            _rPropValue = receivedInt8;
        }

        Serial.print("Left: ");
        Serial.print(_lPropValue);
        Serial.print(", Right: ");
        Serial.print(_rPropValue);
        Serial.println(". ");
    }
};

void setup()
{
    // Initialize built-in LED. 
    pinMode(LED_BLUE, OUTPUT);

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
