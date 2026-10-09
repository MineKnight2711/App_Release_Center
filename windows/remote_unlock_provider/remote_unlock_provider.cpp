#include <windows.h>
#include <credentialprovider.h>
#include <wincred.h>
#include <ntsecapi.h>
#include <security.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <strsafe.h>
#include <intsafe.h>
#include <bcrypt.h>
#include <ncrypt.h>
#include <wincrypt.h>
#include <propkey.h>
#include <sddl.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <new>
#include <string>
#include <vector>

#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "crypt32.lib")
#pragma comment(lib, "credui.lib")
#pragma comment(lib, "ncrypt.lib")
#pragma comment(lib, "secur32.lib")
#pragma comment(lib, "shlwapi.lib")

// {7C74A62C-784B-4D6A-B84E-57EE71A46F39}
const CLSID CLSID_AmcRemoteUnlock = {
    0x7c74a62c, 0x784b, 0x4d6a, {0xb8, 0x4e, 0x57, 0xee, 0x71, 0xa4, 0x6f, 0x39}};

namespace {

long g_dll_refs = 0;
enum FieldId : DWORD {
  kTitle = 0,
  kStatus,
  kSubmit,
  kFieldCount,
};

const CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR kFields[kFieldCount] = {
    {kTitle, CPFT_LARGE_TEXT, const_cast<PWSTR>(L"AMC Remote Unlock"), GUID_NULL},
    {kStatus, CPFT_SMALL_TEXT, const_cast<PWSTR>(L"Waiting for an encrypted request"), GUID_NULL},
    {kSubmit, CPFT_SUBMIT_BUTTON, const_cast<PWSTR>(L"Unlock"), GUID_NULL},
};

struct FieldStatePair {
  CREDENTIAL_PROVIDER_FIELD_STATE cpfs;
  CREDENTIAL_PROVIDER_FIELD_INTERACTIVE_STATE cpfis;
};

const FieldStatePair kFieldStates[kFieldCount] = {
    {CPFS_DISPLAY_IN_BOTH, CPFIS_NONE},
    {CPFS_DISPLAY_IN_SELECTED_TILE, CPFIS_NONE},
    {CPFS_DISPLAY_IN_SELECTED_TILE, CPFIS_NONE},
};

std::wstring DataPath(const wchar_t* name) {
  wchar_t root[MAX_PATH] = {};
  if (FAILED(SHGetFolderPathW(nullptr, CSIDL_COMMON_APPDATA, nullptr, SHGFP_TYPE_CURRENT, root))) {
    return {};
  }
  std::wstring path(root);
  path += L"\\App Management Center\\Remote Unlock\\";
  path += name;
  return path;
}

bool FileExists(const std::wstring& path) {
  return GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

bool ReadBytes(const std::wstring& path, std::vector<unsigned char>* output) {
  HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return false;
  LARGE_INTEGER size = {};
  bool ok = GetFileSizeEx(file, &size) && size.QuadPart > 0 && size.QuadPart <= 4096;
  if (ok) {
    output->resize(static_cast<size_t>(size.QuadPart));
    DWORD read = 0;
    ok = ReadFile(file, output->data(), static_cast<DWORD>(output->size()), &read, nullptr) &&
         read == static_cast<DWORD>(output->size());
  }
  CloseHandle(file);
  if (!ok) output->clear();
  return ok;
}

std::string ReadAscii(const std::wstring& path) {
  std::vector<unsigned char> bytes;
  if (!ReadBytes(path, &bytes)) return {};
  std::string value(bytes.begin(), bytes.end());
  while (!value.empty() && isspace(static_cast<unsigned char>(value.back()))) value.pop_back();
  return value;
}

std::vector<unsigned char> HexBytes(const std::string& value) {
  std::vector<unsigned char> bytes;
  if (value.size() % 2 != 0) return bytes;
  for (size_t i = 0; i < value.size(); i += 2) {
    char* end = nullptr;
    const std::string pair = value.substr(i, 2);
    const long parsed = strtol(pair.c_str(), &end, 16);
    if (end == nullptr || *end != '\0' || parsed < 0 || parsed > 255) return {};
    bytes.push_back(static_cast<unsigned char>(parsed));
  }
  return bytes;
}

uint16_t ReadU16(const unsigned char* value) {
  return static_cast<uint16_t>(value[0] | (value[1] << 8));
}

uint64_t ReadU64(const unsigned char* value) {
  uint64_t result = 0;
  for (int i = 7; i >= 0; --i) result = (result << 8) | value[i];
  return result;
}

uint64_t UnixMillisNow() {
  FILETIME time = {};
  GetSystemTimeAsFileTime(&time);
  ULARGE_INTEGER ticks = {};
  ticks.LowPart = time.dwLowDateTime;
  ticks.HighPart = time.dwHighDateTime;
  return ticks.QuadPart / 10000ULL - 11644473600000ULL;
}

std::wstring Utf8ToWide(const unsigned char* value, size_t length) {
  if (length == 0 || length > INT_MAX) return {};
  const int required = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                            reinterpret_cast<const char*>(value),
                                            static_cast<int>(length), nullptr, 0);
  if (required <= 0) return {};
  std::wstring result(static_cast<size_t>(required), L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                          reinterpret_cast<const char*>(value),
                          static_cast<int>(length), result.data(), required) != required) {
    return {};
  }
  return result;
}

HRESULT CopyField(const CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR& source,
                  CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR** target) {
  *target = static_cast<CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR*>(
      CoTaskMemAlloc(sizeof(CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR)));
  if (*target == nullptr) return E_OUTOFMEMORY;
  **target = source;
  (*target)->pszLabel = nullptr;
  if (source.pszLabel != nullptr) {
    const HRESULT hr = SHStrDupW(source.pszLabel, &(*target)->pszLabel);
    if (FAILED(hr)) {
      CoTaskMemFree(*target);
      *target = nullptr;
      return hr;
    }
  }
  return S_OK;
}

HRESULT InitUnicode(PWSTR value, UNICODE_STRING* output) {
  if (value == nullptr) return E_INVALIDARG;
  const size_t length = wcslen(value);
  USHORT chars = 0;
  HRESULT hr = SizeTToUShort(length, &chars);
  if (FAILED(hr)) return hr;
  output->Length = static_cast<USHORT>(chars * sizeof(wchar_t));
  output->MaximumLength = output->Length;
  output->Buffer = value;
  return S_OK;
}

HRESULT PackCredential(PWSTR domain, PWSTR user, PWSTR password,
                       CREDENTIAL_PROVIDER_USAGE_SCENARIO usage,
                       BYTE** bytes, DWORD* byte_count) {
  PWSTR protected_password = nullptr;
  DWORD protected_chars = 0;
  SetLastError(ERROR_SUCCESS);
  if (CredProtectW(FALSE, password, static_cast<DWORD>(wcslen(password) + 1),
                   nullptr, &protected_chars, nullptr)) return E_UNEXPECTED;
  const DWORD size_error = GetLastError();
  if (size_error != ERROR_INSUFFICIENT_BUFFER) return HRESULT_FROM_WIN32(size_error);
  protected_password = static_cast<PWSTR>(
      CoTaskMemAlloc(protected_chars * sizeof(wchar_t)));
  if (protected_password == nullptr) return E_OUTOFMEMORY;
  if (!CredProtectW(FALSE, password, static_cast<DWORD>(wcslen(password) + 1),
                    protected_password, &protected_chars, nullptr)) {
    const HRESULT hr = HRESULT_FROM_WIN32(GetLastError());
    SecureZeroMemory(protected_password, protected_chars * sizeof(wchar_t));
    CoTaskMemFree(protected_password);
    return hr;
  }

  HRESULT hr = S_OK;
  KERB_INTERACTIVE_UNLOCK_LOGON input = {};
  input.Logon.MessageType = usage == CPUS_UNLOCK_WORKSTATION
                                ? KerbWorkstationUnlockLogon
                                : KerbInteractiveLogon;
  hr = InitUnicode(domain, &input.Logon.LogonDomainName);
  if (SUCCEEDED(hr)) hr = InitUnicode(user, &input.Logon.UserName);
  if (SUCCEEDED(hr)) hr = InitUnicode(protected_password, &input.Logon.Password);
  if (SUCCEEDED(hr)) {
    const DWORD total = sizeof(input) + input.Logon.LogonDomainName.Length +
                        input.Logon.UserName.Length + input.Logon.Password.Length;
    auto* packed = static_cast<KERB_INTERACTIVE_UNLOCK_LOGON*>(CoTaskMemAlloc(total));
    if (packed == nullptr) {
      hr = E_OUTOFMEMORY;
    } else {
      ZeroMemory(packed, total);
      packed->Logon.MessageType = input.Logon.MessageType;
      BYTE* cursor = reinterpret_cast<BYTE*>(packed) + sizeof(*packed);
      auto copy_string = [&](const UNICODE_STRING& source, UNICODE_STRING* target) {
        target->Length = source.Length;
        target->MaximumLength = source.Length;
        CopyMemory(cursor, source.Buffer, source.Length);
        target->Buffer = reinterpret_cast<PWSTR>(cursor - reinterpret_cast<BYTE*>(packed));
        cursor += source.Length;
      };
      copy_string(input.Logon.LogonDomainName, &packed->Logon.LogonDomainName);
      copy_string(input.Logon.UserName, &packed->Logon.UserName);
      copy_string(input.Logon.Password, &packed->Logon.Password);
      *bytes = reinterpret_cast<BYTE*>(packed);
      *byte_count = total;
    }
  }
  SecureZeroMemory(protected_password, protected_chars * sizeof(wchar_t));
  CoTaskMemFree(protected_password);
  return hr;
}

HRESULT NegotiatePackage(ULONG* package) {
  HANDLE lsa = nullptr;
  NTSTATUS status = LsaConnectUntrusted(&lsa);
  if (status != 0) return HRESULT_FROM_NT(status);
  char name[] = NEGOSSP_NAME_A;
  LSA_STRING value = {static_cast<USHORT>(strlen(name)),
                      static_cast<USHORT>(strlen(name) + 1), name};
  status = LsaLookupAuthenticationPackage(lsa, &value, package);
  LsaDeregisterLogonProcess(lsa);
  return status == 0 ? S_OK : HRESULT_FROM_NT(status);
}

bool SplitAccount(const std::wstring& account, std::wstring* domain, std::wstring* user) {
  const size_t separator = account.find(L'\\');
  if (separator == std::wstring::npos || separator == 0 || separator + 1 >= account.size()) {
    return false;
  }
  *domain = account.substr(0, separator);
  *user = account.substr(separator + 1);
  return true;
}

// Whether [account] names the same Windows user as the tile being unlocked.
//
// Compared as SIDs rather than as text. The tile reports whatever name the
// account signs in under -- `MicrosoftAccount\someone@example.com` for a
// Microsoft account, `AzureAD\...` for a work account -- while the desktop can
// only know the SAM name its own process runs as, `MACHINE\someone`. Those two
// strings never match on a Microsoft-account machine, which is the whole of
// Windows 11 Home out of the box, so comparing them as text refused every
// unlock there with "targets a different Windows account". Both names resolve
// to one SID, and that is the identity the check is actually about.
bool AccountMatchesTile(const std::wstring& account, PCWSTR tile_sid_text,
                        PCWSTR tile_qualified_name) {
  PSID tile_sid = nullptr;
  if (!account.empty() && tile_sid_text != nullptr &&
      ConvertStringSidToSidW(tile_sid_text, &tile_sid)) {
    DWORD sid_size = 0;
    DWORD domain_size = 0;
    SID_NAME_USE use = SidTypeUnknown;
    LookupAccountNameW(nullptr, account.c_str(), nullptr, &sid_size, nullptr,
                       &domain_size, &use);
    bool equal = false;
    if (sid_size > 0) {
      std::vector<BYTE> sid(sid_size);
      std::vector<wchar_t> domain(domain_size == 0 ? 1 : domain_size);
      if (LookupAccountNameW(nullptr, account.c_str(), sid.data(), &sid_size,
                             domain.data(), &domain_size, &use)) {
        equal = EqualSid(sid.data(), tile_sid) != FALSE;
      }
    }
    LocalFree(tile_sid);
    if (equal) return true;
  }
  // The name is still worth trying: a SID that will not resolve here should
  // not lock out a plain local account whose names do line up.
  return tile_qualified_name != nullptr &&
         _wcsicmp(account.c_str(), tile_qualified_name) == 0;
}

bool DecryptPending(std::wstring* account, std::wstring* password, std::wstring* error) {
  const std::wstring pending_path = DataPath(L"pending.bin");
  std::vector<unsigned char> encrypted;
  if (!ReadBytes(pending_path, &encrypted)) {
    *error = L"No encrypted unlock request is ready.";
    return false;
  }
  DeleteFileW(pending_path.c_str());

  const std::string thumbprint = ReadAscii(DataPath(L"config.txt"));
  const std::vector<unsigned char> hash = HexBytes(thumbprint);
  if (hash.empty()) {
    *error = L"Remote unlock key configuration is invalid.";
    return false;
  }
  HCERTSTORE store = CertOpenStore(CERT_STORE_PROV_SYSTEM_W, 0, 0,
                                   CERT_SYSTEM_STORE_LOCAL_MACHINE, L"MY");
  if (store == nullptr) return false;
  CRYPT_HASH_BLOB blob = {static_cast<DWORD>(hash.size()),
                          const_cast<BYTE*>(hash.data())};
  PCCERT_CONTEXT cert = CertFindCertificateInStore(
      store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0, CERT_FIND_HASH, &blob, nullptr);
  if (cert == nullptr) {
    CertCloseStore(store, 0);
    *error = L"Remote unlock certificate was not found.";
    return false;
  }
  NCRYPT_KEY_HANDLE key = 0;
  DWORD key_spec = 0;
  BOOL must_free = FALSE;
  const BOOL acquired = CryptAcquireCertificatePrivateKey(
      cert, CRYPT_ACQUIRE_ONLY_NCRYPT_KEY_FLAG | CRYPT_ACQUIRE_SILENT_FLAG,
      nullptr, reinterpret_cast<HCRYPTPROV_OR_NCRYPT_KEY_HANDLE*>(&key),
      &key_spec, &must_free);
  std::vector<unsigned char> plain;
  bool ok = false;
  if (acquired) {
    BCRYPT_OAEP_PADDING_INFO padding = {BCRYPT_SHA256_ALGORITHM, nullptr, 0};
    DWORD plain_size = 0;
    SECURITY_STATUS status = NCryptDecrypt(
        key, encrypted.data(), static_cast<DWORD>(encrypted.size()), &padding,
        nullptr, 0, &plain_size, NCRYPT_PAD_OAEP_FLAG);
    if (status == ERROR_SUCCESS && plain_size > 0 && plain_size <= 1024) {
      plain.resize(plain_size);
      status = NCryptDecrypt(key, encrypted.data(), static_cast<DWORD>(encrypted.size()),
                            &padding, plain.data(), plain_size, &plain_size,
                            NCRYPT_PAD_OAEP_FLAG);
      ok = status == ERROR_SUCCESS;
      plain.resize(ok ? plain_size : 0);
    }
    if (must_free) NCryptFreeObject(key);
  }
  CertFreeCertificateContext(cert);
  CertCloseStore(store, 0);
  SecureZeroMemory(encrypted.data(), encrypted.size());
  if (!ok) {
    *error = L"The encrypted unlock request could not be decrypted.";
    return false;
  }
  ok = false;

  std::vector<unsigned char> challenge_file;
  if (!ReadBytes(DataPath(L"challenge.bin"), &challenge_file) ||
      challenge_file.size() < 48 ||
      memcmp(challenge_file.data(), "AMCCH1", 6) != 0 ||
      plain.size() < 49 || memcmp(plain.data(), "AMC1", 4) != 0 || plain[4] != 1) {
    *error = L"The unlock challenge is invalid.";
  } else {
    const uint64_t challenge_expiry = ReadU64(challenge_file.data() + 6);
    const uint64_t request_expiry = ReadU64(plain.data() + 5);
    const uint64_t now = UnixMillisNow();
    const uint16_t challenge_account_length = ReadU16(challenge_file.data() + 46);
    const uint16_t user_length = ReadU16(plain.data() + 45);
    const uint16_t password_length = ReadU16(plain.data() + 47);
    const size_t expected_challenge = 48ULL + challenge_account_length;
    const size_t expected = 49ULL + user_length + password_length;
    if (now > challenge_expiry || now > request_expiry ||
        request_expiry > challenge_expiry || expected_challenge != challenge_file.size() ||
        expected != plain.size() ||
        memcmp(challenge_file.data() + 14, plain.data() + 13, 32) != 0) {
      *error = L"The unlock request expired or did not match this lock session.";
    } else {
      const std::wstring challenge_account =
          Utf8ToWide(challenge_file.data() + 48, challenge_account_length);
      *account = Utf8ToWide(plain.data() + 49, user_length);
      *password = Utf8ToWide(plain.data() + 49 + user_length, password_length);
      ok = !challenge_account.empty() && !account->empty() && !password->empty() &&
           _wcsicmp(challenge_account.c_str(), account->c_str()) == 0;
      if (!ok) *error = L"The unlock request contained invalid credentials.";
    }
  }
  DeleteFileW(DataPath(L"challenge.bin").c_str());
  SecureZeroMemory(plain.data(), plain.size());
  return ok;
}

class RemoteUnlockCredential final : public ICredentialProviderCredential2 {
 public:
  RemoteUnlockCredential() { InterlockedIncrement(&g_dll_refs); }
  ~RemoteUnlockCredential() {
    CoTaskMemFree(user_sid_);
    CoTaskMemFree(qualified_name_);
    InterlockedDecrement(&g_dll_refs);
  }

  HRESULT Initialize(ICredentialProviderUser* user, CREDENTIAL_PROVIDER_USAGE_SCENARIO usage) {
    usage_ = usage;
    HRESULT hr = user->GetSid(&user_sid_);
    if (SUCCEEDED(hr)) hr = user->GetStringValue(PKEY_Identity_QualifiedUserName, &qualified_name_);
    return hr;
  }

  IFACEMETHODIMP QueryInterface(REFIID iid, void** value) override {
    if (value == nullptr) return E_POINTER;
    *value = nullptr;
    if (iid == IID_IUnknown || iid == IID_ICredentialProviderCredential) {
      *value = static_cast<ICredentialProviderCredential*>(this);
    } else if (iid == IID_ICredentialProviderCredential2) {
      *value = static_cast<ICredentialProviderCredential2*>(this);
    } else {
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
  IFACEMETHODIMP_(ULONG) Release() override {
    const long count = InterlockedDecrement(&refs_);
    if (count == 0) delete this;
    return count;
  }
  IFACEMETHODIMP Advise(ICredentialProviderCredentialEvents*) override { return S_OK; }
  IFACEMETHODIMP UnAdvise() override { return S_OK; }
  IFACEMETHODIMP SetSelected(BOOL* auto_logon) override {
    *auto_logon = FileExists(DataPath(L"pending.bin"));
    return S_OK;
  }
  IFACEMETHODIMP SetDeselected() override { return S_OK; }
  IFACEMETHODIMP GetFieldState(DWORD id, CREDENTIAL_PROVIDER_FIELD_STATE* state,
                               CREDENTIAL_PROVIDER_FIELD_INTERACTIVE_STATE* interactive) override {
    if (id >= kFieldCount) return E_INVALIDARG;
    *state = kFieldStates[id].cpfs;
    *interactive = kFieldStates[id].cpfis;
    return S_OK;
  }
  IFACEMETHODIMP GetStringValue(DWORD id, PWSTR* value) override {
    if (id == kTitle) return SHStrDupW(L"AMC Remote Unlock", value);
    if (id == kStatus) return SHStrDupW(
        FileExists(DataPath(L"pending.bin")) ? L"Encrypted request received"
                                              : L"Waiting for the linked phone",
        value);
    return E_INVALIDARG;
  }
  IFACEMETHODIMP GetBitmapValue(DWORD, HBITMAP*) override { return E_NOTIMPL; }
  IFACEMETHODIMP GetCheckboxValue(DWORD, BOOL*, PWSTR*) override { return E_NOTIMPL; }
  IFACEMETHODIMP GetSubmitButtonValue(DWORD id, DWORD* adjacent) override {
    if (id != kSubmit) return E_INVALIDARG;
    *adjacent = kStatus;
    return S_OK;
  }
  IFACEMETHODIMP GetComboBoxValueCount(DWORD, DWORD*, DWORD*) override { return E_NOTIMPL; }
  IFACEMETHODIMP GetComboBoxValueAt(DWORD, DWORD, PWSTR*) override { return E_NOTIMPL; }
  IFACEMETHODIMP SetStringValue(DWORD, PCWSTR) override { return E_NOTIMPL; }
  IFACEMETHODIMP SetCheckboxValue(DWORD, BOOL) override { return E_NOTIMPL; }
  IFACEMETHODIMP SetComboBoxSelectedValue(DWORD, DWORD) override { return E_NOTIMPL; }
  IFACEMETHODIMP CommandLinkClicked(DWORD) override { return E_NOTIMPL; }

  IFACEMETHODIMP GetSerialization(
      CREDENTIAL_PROVIDER_GET_SERIALIZATION_RESPONSE* response,
      CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION* serialization,
      PWSTR* status_text, CREDENTIAL_PROVIDER_STATUS_ICON* status_icon) override {
    *response = CPGSR_NO_CREDENTIAL_NOT_FINISHED;
    *status_text = nullptr;
    *status_icon = CPSI_NONE;
    ZeroMemory(serialization, sizeof(*serialization));
    std::wstring account;
    std::wstring password;
    std::wstring error;
    HRESULT hr = E_FAIL;
    if (!DecryptPending(&account, &password, &error)) {
      SHStrDupW(error.c_str(), status_text);
      *status_icon = CPSI_ERROR;
      return S_OK;
    }
    if (!AccountMatchesTile(account, user_sid_, qualified_name_)) {
      error = L"The request targets a different Windows account.";
    } else {
      std::wstring domain;
      std::wstring user;
      if (SplitAccount(account, &domain, &user)) {
        hr = PackCredential(domain.data(), user.data(), password.data(), usage_,
                            &serialization->rgbSerialization,
                            &serialization->cbSerialization);
        if (SUCCEEDED(hr)) hr = NegotiatePackage(&serialization->ulAuthenticationPackage);
        if (SUCCEEDED(hr)) {
          serialization->clsidCredentialProvider = CLSID_AmcRemoteUnlock;
          *response = CPGSR_RETURN_CREDENTIAL_FINISHED;
        }
      }
    }
    SecureZeroMemory(password.data(), password.size() * sizeof(wchar_t));
    if (FAILED(hr)) {
      if (serialization->rgbSerialization != nullptr) {
        SecureZeroMemory(serialization->rgbSerialization, serialization->cbSerialization);
        CoTaskMemFree(serialization->rgbSerialization);
        serialization->rgbSerialization = nullptr;
        serialization->cbSerialization = 0;
      }
      if (error.empty()) error = L"Windows could not prepare the unlock credential.";
      SHStrDupW(error.c_str(), status_text);
      *status_icon = CPSI_ERROR;
      return S_OK;
    }
    return S_OK;
  }

  IFACEMETHODIMP ReportResult(NTSTATUS status, NTSTATUS,
                              PWSTR* text, CREDENTIAL_PROVIDER_STATUS_ICON* icon) override {
    *text = nullptr;
    *icon = CPSI_NONE;
    if (status != 0) {
      SHStrDupW(L"Windows rejected the remote unlock password.", text);
      *icon = CPSI_ERROR;
    }
    return S_OK;
  }
  IFACEMETHODIMP GetUserSid(PWSTR* sid) override {
    return user_sid_ == nullptr ? E_UNEXPECTED : SHStrDupW(user_sid_, sid);
  }
 private:
  long refs_ = 1;
  CREDENTIAL_PROVIDER_USAGE_SCENARIO usage_ = CPUS_INVALID;
  PWSTR user_sid_ = nullptr;
  PWSTR qualified_name_ = nullptr;
};

class RemoteUnlockProvider final : public ICredentialProvider,
                                   public ICredentialProviderSetUserArray {
 public:
  RemoteUnlockProvider() {
    InitializeCriticalSection(&lock_);
    InterlockedIncrement(&g_dll_refs);
  }
  ~RemoteUnlockProvider() {
    UnAdvise();
    if (credential_ != nullptr) credential_->Release();
    if (users_ != nullptr) users_->Release();
    DeleteCriticalSection(&lock_);
    InterlockedDecrement(&g_dll_refs);
  }

  IFACEMETHODIMP QueryInterface(REFIID iid, void** value) override {
    if (value == nullptr) return E_POINTER;
    *value = nullptr;
    if (iid == IID_IUnknown || iid == IID_ICredentialProvider) {
      *value = static_cast<ICredentialProvider*>(this);
    } else if (iid == IID_ICredentialProviderSetUserArray) {
      *value = static_cast<ICredentialProviderSetUserArray*>(this);
    } else {
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
  IFACEMETHODIMP_(ULONG) Release() override {
    const long count = InterlockedDecrement(&refs_);
    if (count == 0) delete this;
    return count;
  }
  IFACEMETHODIMP SetUsageScenario(CREDENTIAL_PROVIDER_USAGE_SCENARIO usage, DWORD) override {
    if (usage != CPUS_LOGON && usage != CPUS_UNLOCK_WORKSTATION) return E_NOTIMPL;
    usage_ = usage;
    return S_OK;
  }
  IFACEMETHODIMP SetSerialization(const CREDENTIAL_PROVIDER_CREDENTIAL_SERIALIZATION*) override {
    return E_NOTIMPL;
  }
  IFACEMETHODIMP Advise(ICredentialProviderEvents* events, UINT_PTR context) override {
    UnAdvise();
    EnterCriticalSection(&lock_);
    events_ = events;
    events_->AddRef();
    context_ = context;
    LeaveCriticalSection(&lock_);
    stop_event_ = CreateEventW(nullptr, TRUE, FALSE, nullptr);
    thread_ = CreateThread(nullptr, 0, WatchThread, this, 0, nullptr);
    return thread_ != nullptr ? S_OK : HRESULT_FROM_WIN32(GetLastError());
  }
  IFACEMETHODIMP UnAdvise() override {
    if (stop_event_ != nullptr) SetEvent(stop_event_);
    if (thread_ != nullptr) {
      WaitForSingleObject(thread_, 3000);
      CloseHandle(thread_);
      thread_ = nullptr;
    }
    if (stop_event_ != nullptr) {
      CloseHandle(stop_event_);
      stop_event_ = nullptr;
    }
    EnterCriticalSection(&lock_);
    if (events_ != nullptr) {
      events_->Release();
      events_ = nullptr;
    }
    LeaveCriticalSection(&lock_);
    return S_OK;
  }
  IFACEMETHODIMP GetFieldDescriptorCount(DWORD* count) override {
    *count = kFieldCount;
    return S_OK;
  }
  IFACEMETHODIMP GetFieldDescriptorAt(DWORD index,
                                      CREDENTIAL_PROVIDER_FIELD_DESCRIPTOR** field) override {
    return index < kFieldCount ? CopyField(kFields[index], field) : E_INVALIDARG;
  }
  IFACEMETHODIMP GetCredentialCount(DWORD* count, DWORD* default_index,
                                    BOOL* auto_logon) override {
    HRESULT hr = EnsureCredential();
    *count = SUCCEEDED(hr) && credential_ != nullptr ? 1 : 0;
    const bool pending = *count == 1 && FileExists(DataPath(L"pending.bin"));
    *default_index = pending ? 0 : CREDENTIAL_PROVIDER_NO_DEFAULT;
    *auto_logon = pending ? TRUE : FALSE;
    return S_OK;
  }
  IFACEMETHODIMP GetCredentialAt(DWORD index, ICredentialProviderCredential** credential) override {
    if (index != 0 || credential_ == nullptr) return E_INVALIDARG;
    return credential_->QueryInterface(IID_PPV_ARGS(credential));
  }
  IFACEMETHODIMP SetUserArray(ICredentialProviderUserArray* users) override {
    if (users_ != nullptr) users_->Release();
    users_ = users;
    users_->AddRef();
    if (credential_ != nullptr) {
      credential_->Release();
      credential_ = nullptr;
    }
    return S_OK;
  }

 private:
  HRESULT EnsureCredential() {
    if (credential_ != nullptr) return S_OK;
    if (users_ == nullptr) return E_UNEXPECTED;
    DWORD count = 0;
    HRESULT hr = users_->GetCount(&count);
    if (FAILED(hr) || count == 0) return E_UNEXPECTED;
    ICredentialProviderUser* user = nullptr;
    hr = users_->GetAt(0, &user);
    if (SUCCEEDED(hr)) {
      credential_ = new (std::nothrow) RemoteUnlockCredential();
      if (credential_ == nullptr) {
        hr = E_OUTOFMEMORY;
      } else {
        hr = credential_->Initialize(user, usage_);
        if (FAILED(hr)) {
          credential_->Release();
          credential_ = nullptr;
        }
      }
      user->Release();
    }
    return hr;
  }

  static DWORD WINAPI WatchThread(void* context) {
    auto* self = static_cast<RemoteUnlockProvider*>(context);
    bool saw_pending = FileExists(DataPath(L"pending.bin"));
    while (WaitForSingleObject(self->stop_event_, 500) == WAIT_TIMEOUT) {
      const bool pending = FileExists(DataPath(L"pending.bin"));
      if (pending && !saw_pending) {
        EnterCriticalSection(&self->lock_);
        if (self->events_ != nullptr) self->events_->CredentialsChanged(self->context_);
        LeaveCriticalSection(&self->lock_);
      }
      saw_pending = pending;
    }
    return 0;
  }

  long refs_ = 1;
  CREDENTIAL_PROVIDER_USAGE_SCENARIO usage_ = CPUS_INVALID;
  ICredentialProviderUserArray* users_ = nullptr;
  RemoteUnlockCredential* credential_ = nullptr;
  ICredentialProviderEvents* events_ = nullptr;
  UINT_PTR context_ = 0;
  CRITICAL_SECTION lock_ = {};
  HANDLE stop_event_ = nullptr;
  HANDLE thread_ = nullptr;
};

class ClassFactory final : public IClassFactory {
 public:
  ClassFactory() { InterlockedIncrement(&g_dll_refs); }
  ~ClassFactory() { InterlockedDecrement(&g_dll_refs); }
  IFACEMETHODIMP QueryInterface(REFIID iid, void** value) override {
    if (value == nullptr) return E_POINTER;
    *value = nullptr;
    if (iid != IID_IUnknown && iid != IID_IClassFactory) return E_NOINTERFACE;
    *value = static_cast<IClassFactory*>(this);
    AddRef();
    return S_OK;
  }
  IFACEMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
  IFACEMETHODIMP_(ULONG) Release() override {
    const long count = InterlockedDecrement(&refs_);
    if (count == 0) delete this;
    return count;
  }
  IFACEMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** value) override {
    if (outer != nullptr) return CLASS_E_NOAGGREGATION;
    auto* provider = new (std::nothrow) RemoteUnlockProvider();
    if (provider == nullptr) return E_OUTOFMEMORY;
    const HRESULT hr = provider->QueryInterface(iid, value);
    provider->Release();
    return hr;
  }
  IFACEMETHODIMP LockServer(BOOL lock) override {
    lock ? InterlockedIncrement(&g_dll_refs) : InterlockedDecrement(&g_dll_refs);
    return S_OK;
  }
 private:
  long refs_ = 1;
};

}  // namespace

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, void*) {
  if (reason == DLL_PROCESS_ATTACH) {
    DisableThreadLibraryCalls(instance);
  }
  return TRUE;
}

STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, LPVOID* value) {
  if (clsid != CLSID_AmcRemoteUnlock) return CLASS_E_CLASSNOTAVAILABLE;
  auto* factory = new (std::nothrow) ClassFactory();
  if (factory == nullptr) return E_OUTOFMEMORY;
  const HRESULT hr = factory->QueryInterface(iid, value);
  factory->Release();
  return hr;
}

STDAPI DllCanUnloadNow() {
  return g_dll_refs == 0 ? S_OK : S_FALSE;
}
