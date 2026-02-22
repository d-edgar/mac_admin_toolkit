# Jamf Stuff

This repository provides **Jamf Pro Extension Attributes (EAs)** and supporting scripts to monitor and report on the health of **Microsoft Defender for Endpoint (MDE)** on macOS devices. This repository will also include scripts leveraged and used within the Jamf Pro envionrment.

By leveraging these EAs and scripts, you can create **Smart Groups** and **Advanced Searches** in Jamf Pro to dynamically identify Macs that are out of compliance — for example, those with network protection stopped, real-time protection disabled, or outdated engine versions.

---
## Overview for Jamf "Stuff" Scripts
The scripts in this folder are a collection of work we have developed, used, and gathered from a variety of sources across the internet. While some scripts originated elsewhere, the majority reflect significant effort to adapt, refine, and ensure they function properly within our environment.

Scripts of note:
- **UninstallSoftware.sh**
- **ChangeNameScript.sh**
- **SetAssetTagJamf.sh**
- **CustomTriggerEvent4.sh**
- **InstallRosettaIfNeeded.sh**


---

## 📋 Overview for MDE and EA

The scripts use the [`mdatp`](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/mac-install-manually) command-line tool (installed with Defender for Endpoint) to query health fields such as:

- **Network Protection**
- **Real-Time Protection**
- **Tamper Protection**
- **Healthy flag**
- **Onboarding/EDR status**
- **App and Engine versions**
- **Signature/Definition updates** (optional)

Each script is formatted for Jamf Extension Attributes, returning values inside `<result> … </result>`.

---

## 🛠️ Extension Attributes Included

### Network Protection
- `network_protection_status`  
- `network_protection_enforcement_level`  

### Real-Time Protection
- `real_time_protection_enabled`  
- `real_time_protection_available`  
- `real_time_protection_subsystem`  

### Tamper Protection
- `tamper_protection` (block | audit | disabled)  

### General Health
- `healthy` (overall status)  

### App / Engine Versions
- `app_version`  
- `engine_version`  

### EDR
- `is_onboarded` or `org_id` (depending on Defender version)  

---

## 🚀 Usage

1. **Upload to Jamf Pro**
   - In **Jamf Pro → Settings → Computer Management → Extension Attributes**, create a new EA.
   - Paste the script into the “Script” section.
   - Set the **Data Type**:
     - *String* for text values (subsystems, versions, tamper protection).
     - *Boolean* for true/false flags.

2. **Inventory Update**
   - Run `sudo jamf recon` on a test Mac to populate values.
   - Verify EA results appear in the computer record.

3. **Smart Groups**
   - Examples:
     - Macs with **Network Protection stopped/disabled**  
       → EA `MDE: Network Protection Status` contains `stopped`  
     - Macs with **RTP disabled**  
       → EA `MDE: RTP Enabled` equals `false`  
     - Macs **not onboarded**  
       → EA `MDE: EDR Onboarded` equals `false` or `Unknown`  
---

## 🔍 Requirements

- macOS with **Microsoft Defender for Endpoint** installed.  
- `mdatp` binary available at `/usr/local/bin/mdatp` (or in `$PATH`).  
- Jamf Pro with permission to create and assign Extension Attributes.

---

## 📖 References

- [Microsoft Docs – Defender for Endpoint on macOS](https://learn.microsoft.com/microsoft-365/security/defender-endpoint/mac-whatsnew)  
- [Jamf Pro – Extension Attributes](https://learn.jamf.com/bundle/jamf-pro-documentation-current/page/Computer_Extension_Attributes.html)  

---

## 🤝 Contributing

Pull requests are welcome! If you’d like to add more fields, fix scripts, or extend functionality, please open an issue or submit a PR.

---

## 📜 License

MIT License. See [LICENSE](LICENSE) for details.