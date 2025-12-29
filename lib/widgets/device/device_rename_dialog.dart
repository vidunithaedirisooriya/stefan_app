import 'package:flutter/material.dart';

class DeviceRenameDialog {
  static Future<String?> show(BuildContext context, String currentName) async {
    TextEditingController nameController = TextEditingController(text: currentName);
    
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Rename Device'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter device name',
                ),
                maxLength: 20,
              ),
              const SizedBox(height: 8),
              const Text(
                'Effective after restarting the fan.Renaming as nothing will reset to factory name',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                String newName = nameController.text.trim();
                Navigator.pop(context, newName);
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );
  }
}