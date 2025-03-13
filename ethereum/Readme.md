```
set -o allexport
source .env
set +o allexport
```

### TODO:
A list of todos:
- Currently fee is not included in the estimation calculation
- Slippage is also not included, not sure if this is important
- Binary search given the range is still too slow