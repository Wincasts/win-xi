#pragma once
#include <windows.h>

// Small device-independent policies so failure paths can be tested without a client.
// Device supplies the D3D8 state-block methods; configure records changed states.
namespace NameStateBlocks {
    template<class Device, class Configure>
    bool Record(Device* device, DWORD& token, Configure configure) {
        if (token != 0) { return true; }
        if (FAILED(device->BeginStateBlock())) { return false; }
        configure(device);
        if (FAILED(device->EndStateBlock(&token))) {
            token = 0;
            return false;
        }
        return token != 0;
    }

    template<class Device>
    bool Activate(Device* device, DWORD saved, DWORD names, bool& captured, bool keep) {
        if (!captured || !keep) {
            captured = false;
            if (FAILED(device->CaptureStateBlock(saved))) { return false; }
            captured = true;
        }
        if (FAILED(device->ApplyStateBlock(names))) {
            // Applying can fail after changing some states. Best-effort restoration,
            // but never trust this run's capture for another draw after a failure.
            device->ApplyStateBlock(saved);
            captured = false;
            return false;
        }
        return true;
    }

    template<class Device>
    bool Restore(Device* device, DWORD saved, bool& captured) {
        if (FAILED(device->ApplyStateBlock(saved))) {
            captured = false;
            return false;
        }
        return true;
    }
}
