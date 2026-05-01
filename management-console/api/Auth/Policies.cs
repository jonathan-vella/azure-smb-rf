namespace ManagementConsole.Api.Auth;

public static class Policies
{
    public const string PartnerStaff = "PartnerStaff";

    /// <summary>
    /// App role value granted (via group membership) to users allowed to use
    /// the partner management console. The Entra group of the same name is
    /// created in preprovision.ps1 and assigned this app role on the API SP.
    /// </summary>
    public const string ManagementRole = "AZURE-SMB-RF-MANAGEMENT";
}
