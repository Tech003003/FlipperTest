# FlipperTest
Random flipper zero scripts I'm attempting to write. This is meant for myself and not meant for public.

## Discord Webhook Helper

Use the provided PowerShell script to send the contents of a `.txt` file to your Discord webhook.

```powershell
# Example usage
./send-to-discord.ps1 -FilePath path/to/message.txt
```

The `-WebhookUrl` parameter defaults to your saved webhook, but you can override it when needed.
