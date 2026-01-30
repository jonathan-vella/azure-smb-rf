# SMB Landing Zone Deployment Demo
# Generate with: docker run --rm -v $PWD:/vhs ghcr.io/charmbracelet/vhs docs/demo.tape
# Or if VHS installed: vhs docs/demo.tape

# Output settings
Output docs/images/deploy-demo.gif

# Terminal settings
Set Shell "pwsh"
Set FontFamily "Cascadia Code"
Set FontSize 18
Set Width 1200
Set Height 700
Set Padding 20
Set Theme "Catppuccin Mocha"
Set WindowBar Colorful
Set BorderRadius 8
Set Margin 20
Set MarginFill "#1e1e2e"
Set TypingSpeed 50ms

# Title frame
Type "# Azure SMB Landing Zone - Deployment Demo"
Enter
Sleep 1s
Type "clear"
Enter
Sleep 500ms

# Navigate to deployment folder
Type "cd infra/bicep/smb-landing-zone"
Enter
Sleep 500ms

# Show available scenarios
Type "# Available deployment scenarios:"
Enter
Sleep 500ms
Type "echo 'baseline  (~$48/mo)  - NAT Gateway only'"
Enter
Sleep 300ms
Type "echo 'firewall  (~$336/mo) - Azure Firewall + UDR'"
Enter
Sleep 300ms
Type "echo 'vpn       (~$187/mo) - VPN Gateway'"
Enter
Sleep 300ms
Type "echo 'full      (~$476/mo) - Firewall + VPN + UDR'"
Enter
Sleep 1s

# Run What-If first
Type "# Preview deployment with What-If analysis"
Enter
Sleep 500ms
Type "./deploy.ps1 -Scenario baseline -WhatIf"
Enter
Sleep 2s

# Simulate What-If output (using Hide to fake the output)
Hide
Type "clear"
Enter
Show

Type "# What-If analysis shows resources to be created:"
Enter
Sleep 300ms
Type "echo '  + rg-hub-slz-swc'"
Enter
Sleep 200ms
Type "echo '  + rg-spoke-prod-swc'"
Enter
Sleep 200ms
Type "echo '  + rg-migrate-slz-swc'"
Enter
Sleep 200ms
Type "echo '  + rg-monitor-slz-swc'"
Enter
Sleep 200ms
Type "echo '  + rg-backup-slz-swc'"
Enter
Sleep 200ms
Type "echo '  + Microsoft.Network/virtualNetworks/vnet-hub-slz-swc'"
Enter
Sleep 200ms
Type "echo '  + Microsoft.Network/bastionHosts/bas-hub-slz-swc'"
Enter
Sleep 200ms
Type "echo '  + ... (20+ resources)'"
Enter
Sleep 1.5s

# Deploy baseline
Type "# Deploy the baseline scenario"
Enter
Sleep 500ms
Type "./deploy.ps1 -Scenario baseline -NonInteractive"
Enter
Sleep 1s

# Simulate deployment progress
Hide
Type "clear"
Enter
Show

Type "🚀 Starting deployment: baseline scenario"
Enter
Sleep 300ms
Type "📍 Region: swedencentral"
Enter
Sleep 300ms
Type "💰 Estimated cost: ~$48/month"
Enter
Sleep 500ms
Type ""
Enter
Type "⏳ Creating resource groups..."
Enter
Sleep 800ms
Type "✅ rg-hub-slz-swc"
Enter
Sleep 300ms
Type "✅ rg-spoke-prod-swc"
Enter
Sleep 300ms
Type "✅ rg-migrate-slz-swc"
Enter
Sleep 300ms
Type "✅ rg-monitor-slz-swc"
Enter
Sleep 300ms
Type "✅ rg-backup-slz-swc"
Enter
Sleep 500ms
Type ""
Enter
Type "⏳ Deploying infrastructure..."
Enter
Sleep 1s
Type "✅ Hub VNet deployed"
Enter
Sleep 400ms
Type "✅ Spoke VNet deployed"
Enter
Sleep 400ms
Type "✅ NAT Gateway deployed"
Enter
Sleep 400ms
Type "✅ Azure Bastion deployed"
Enter
Sleep 400ms
Type "✅ Private DNS Zone deployed"
Enter
Sleep 400ms
Type "✅ Azure Migrate Project deployed"
Enter
Sleep 400ms
Type "✅ Log Analytics Workspace deployed"
Enter
Sleep 400ms
Type "✅ Recovery Services Vault deployed"
Enter
Sleep 500ms
Type ""
Enter
Type "🎉 Deployment complete!"
Enter
Sleep 2s

# Final message
Type ""
Enter
Type "# Try other scenarios: firewall, vpn, or full"
Enter
Sleep 2s
