from bson import ObjectId

from app.services import shared_devices
from app.services.shared_devices import parse_device_ids, user_scope_filter, with_shared_devices

USER = {"_id": ObjectId("65dec42fbb74c16d06c15b57")}


def test_parse_device_ids_handles_blanks_and_spaces():
    assert parse_device_ids("") == []
    assert parse_device_ids(" ESP32_21E5F0 , PLAYBACK_DEVICE_REC ,,") == ["ESP32_21E5F0", "PLAYBACK_DEVICE_REC"]


def test_with_shared_devices_keeps_own_devices_first_without_duplicates(monkeypatch):
    monkeypatch.setattr(shared_devices, "shared_device_ids", lambda: ["ESP32_21E5F0", "PLAYBACK_DEVICE_REC"])
    assert with_shared_devices(["MY_DEVICE", "ESP32_21E5F0"]) == ["MY_DEVICE", "ESP32_21E5F0", "PLAYBACK_DEVICE_REC"]
    assert with_shared_devices([]) == ["ESP32_21E5F0", "PLAYBACK_DEVICE_REC"]


def test_user_scope_filter_includes_shared_devices(monkeypatch):
    monkeypatch.setattr(shared_devices, "shared_device_ids", lambda: ["ESP32_21E5F0"])
    assert user_scope_filter(USER) == {
        "$or": [{"user_id": "65dec42fbb74c16d06c15b57"}, {"device_id": {"$in": ["ESP32_21E5F0"]}}]
    }


def test_user_scope_filter_is_unchanged_without_shared_devices(monkeypatch):
    monkeypatch.setattr(shared_devices, "shared_device_ids", lambda: [])
    assert user_scope_filter(USER) == {"user_id": "65dec42fbb74c16d06c15b57"}
    assert with_shared_devices(["MY_DEVICE"]) == ["MY_DEVICE"]
