package oidcprovider

import (
	"flag"
	"strings"

	"github.com/grepplabs/kafka-proxy/pkg/apis"
	"github.com/grepplabs/kafka-proxy/pkg/registry"
)

func init() {
	registry.NewComponentInterface(new(apis.TokenProviderFactory))
	registry.Register(new(Factory), "oidc-provider")
}

func (f *pluginMeta) flagSet() *flag.FlagSet {
	fs := flag.NewFlagSet("oidc provider settings", flag.ContinueOnError)
	return fs
}

type pluginMeta struct {
	timeout int

	credentialsWatch bool
	credentialsFile  string
	targetAudience   string

	grantType    string
	clientID     string
	clientSecret string
	tokenURL     string
	scopes       string
	username     string
	password     string
}

// Factory type
type Factory struct {
}

// New implements apis.TokenProviderFactory
func (t *Factory) New(params []string) (apis.TokenProvider, error) {
	pluginMeta := &pluginMeta{}
	fs := pluginMeta.flagSet()
	fs.IntVar(&pluginMeta.timeout, "timeout", 10, "Request timeout in seconds")
	fs.StringVar(&pluginMeta.credentialsFile, "credentials-file", "", "Location of the JSON file with the application credentials")
	fs.BoolVar(&pluginMeta.credentialsWatch, "credentials-watch", true, "Watch credential for reload")
	fs.StringVar(&pluginMeta.targetAudience, "target-audience", "", "URI of audience claim")
	fs.StringVar(&pluginMeta.grantType, "grant-type", "", "OAuth grant type: client_credentials (default) or password")
	fs.StringVar(&pluginMeta.clientID, "client-id", "", "OAuth client ID. Used when credentials-file is not provided")
	fs.StringVar(&pluginMeta.clientSecret, "client-secret", "", "OAuth client secret. Used when credentials-file is not provided")
	fs.StringVar(&pluginMeta.tokenURL, "token-url", "", "OAuth token endpoint URL. Used when credentials-file is not provided")
	fs.StringVar(&pluginMeta.scopes, "scopes", "", "Comma-separated OAuth scopes. Used when credentials-file is not provided")
	fs.StringVar(&pluginMeta.username, "username", "", "Username for grant-type=password")
	fs.StringVar(&pluginMeta.password, "password", "", "Password for grant-type=password")

	err := fs.Parse(params)
	if err != nil {
		return nil, err
	}
	options := TokenProviderOptions{
		Timeout:          pluginMeta.timeout,
		CredentialsWatch: pluginMeta.credentialsWatch,
		CredentialsFile:  pluginMeta.credentialsFile,
		TargetAudience:   pluginMeta.targetAudience,
		GrantType:        pluginMeta.grantType,
		ClientID:         pluginMeta.clientID,
		ClientSecret:     pluginMeta.clientSecret,
		TokenURL:         pluginMeta.tokenURL,
		Scopes:           splitCSV(pluginMeta.scopes),
		Username:         pluginMeta.username,
		Password:         pluginMeta.password,
	}

	return NewTokenProvider(options)
}

func splitCSV(csv string) []string {
	if strings.TrimSpace(csv) == "" {
		return nil
	}
	parts := strings.Split(csv, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		v := strings.TrimSpace(p)
		if v != "" {
			out = append(out, v)
		}
	}
	return out
}
