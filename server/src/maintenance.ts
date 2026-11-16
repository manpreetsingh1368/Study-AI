import "dotenv/config";
import { openDatabase } from "./database/db.js";
import { existsSync, readdirSync, statSync, unlinkSync } from "node:fs";
import { join } from "node:path";
