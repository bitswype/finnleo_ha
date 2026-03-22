<!--
Copyright 2026 Chris Keeser

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# Contributing

Thank you for your interest in contributing to the Finnleo SaunaLogic2 Home Assistant integration guide! This project thrives on community knowledge, especially from other Sauna360 sauna owners.

## How You Can Help

### Report Your Device

If you have a Sauna360-family sauna (Finnleo, Tylo, Helo, Amerec, Kastor) with a SaunaLogic2 controller:

1. **Confirm compatibility** — Does the `tylohelo_sl2_sauna.yaml` device definition work with your sauna? Open an issue to report success or failure.
2. **Report your Tuya product ID** — If your product ID differs from `acl5qrawgmjajabn`, let us know so we can add it to the device definition.
3. **Discover new data points** — If your sauna has features not documented here (infrared mode, steam, different light options), help us map the DPs. **Warning:** Probe DPs one at a time. Requesting many unknown DPs at once can lock out the device until power-cycled.

### Improve Documentation

- Fix typos, clarify instructions, add screenshots
- Document the integration process on different platforms (Android vs iOS differences, different Smart Life app versions)
- Translate to other languages
- Add HA dashboard examples, automation ideas, or Lovelace cards

### Upstream the Device Definition

The ultimate goal is to get the `tylohelo_sl2_sauna.yaml` device definition included in the [tuya_local](https://github.com/make-all/tuya_local) project itself, so future users don't need to copy files manually. If you want to help with this:

1. Fork [tuya_local](https://github.com/make-all/tuya_local)
2. Add `tylohelo_sl2_sauna.yaml` to the `custom_components/tuya_local/devices/` directory
3. Open a PR with the device definition and a link back to this repo for documentation
4. See tuya_local's [contribution guidelines](https://github.com/make-all/tuya_local/blob/main/CONTRIBUTING.md) for their specific requirements

## Submitting Changes

1. **Fork** this repository
2. **Create a branch** for your change (`git checkout -b my-improvement`)
3. **Make your changes** and commit with clear messages
4. **Open a Pull Request** describing what you changed and why

## Reporting Issues

Open a GitHub issue if:
- The device definition doesn't work with your sauna
- You found a new DP or a different DP mapping
- The setup instructions are unclear or incorrect
- You have a Sauna360 sauna with a different controller model

Please include:
- Your sauna brand and model
- Your SaunaLogic2 firmware version (visible on the controller's info screen)
- Your Tuya product ID (from the Tuya developer console)
- What worked and what didn't

## Code of Conduct

Be kind. We're all just trying to make our saunas smarter.

## Security

**Never include credentials, device IDs, local keys, IP addresses, or other personal information in issues or PRs.** Use placeholders like `<your-device-id>` and `<your-local-key>`.

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.
