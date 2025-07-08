## 🪟 Running Scripts on Windows via WSL

All scripts in this suite are designed to operate seamlessly on Linux and macOS systems.
For Windows users, the recommended approach is to utilize Windows Subsystem for Linux (WSL), which allows you to run a Linux environment directly within Windows.

### ✅ Setting Up WSL

1. **Enable WSL**:
    - Open PowerShell as Administrator and execute:
      ```powershell
      wsl --install
      ```
    - This command installs WSL along with the default Ubuntu distribution.

2. **Restart Your Computer**:
    - After installation, reboot your system to complete the setup.

3. **Initialize Ubuntu**:
    - Launch the Ubuntu application from the Start menu.
    - Set up your UNIX username and password as prompted.

*For more detailed instructions, refer to the official Microsoft documentation: [Install WSL](https://learn.microsoft.com/en-us/windows/wsl/install)*

### 🚀 Executing Scripts

Once WSL is set up:

1. **Access Your Scripts**:
    - Navigate to your script directory. If your scripts are located in `C:\Users\YourName\Projects`, you can access them in WSL via:
      ```bash
      cd /mnt/c/Users/YourName/Projects
      ```

2. **Make the Script Executable**:
    - Ensure the script has execute permissions:
      ```bash
      chmod +x your_script.sh
      ```

3. **Run the Script**:
    - Execute the script using:
      ```bash
      ./your_script.sh
      ```

*Note*: If you prefer using PowerShell, you can run the script with:
```powershell
wsl bash /mnt/c/Users/YourName/Projects/your_script.sh
```

### ⚠️ API Usage Advisory

Some scripts interact with external APIs (e.g., Vultr, RunCloud).
To prevent exceeding API rate limits, it's advisable to run these scripts no more than once per week.
Always verify the specific API's usage policies to ensure compliance.